#!/bin/bash
#set -e
branch="develop"
app_sln_url=`find . -name *.sln | awk -F / '{print $2}'`
updata_number=`git log origin/$branch --grep=".*cicd.*"  --pretty=format:"" --name-only  -1 |  grep -v "^$" | sed  s/"^"$app_sln_url"\///g"  | awk -F / '{print $1}' | uniq `
echo "本次触发程序列表: $updata_number"
echo "本次版本号为 $CI_COMMIT_SHORT_SHA"

for i in $updata_number
do
  netcoreapp=`cat app_service_list.js | grep $i | wc -l`
  if  [[ $netcoreapp != 0 ]] ; then
  echo " $i is ok"
  else
    echo "1,$i 程序在非部署程序列表名单中，请在app_service_list.js中添加该项目"
    continue
  fi
  #获取程序配置路径
  app_name_url=`find  /cicd_tmp_data  -name $i`
  #获取当前为版本
  #$CI_COMMIT_SHORT_SHA
  date=`date +%Y%m%d`
  #替换大小写和.符号
  updata_name=`echo "$i" | sed s/"\."//g |  tr  A-Z a-z`
  #获取程序配置数据
  api_url=`curl -k -u "${CATTLE_ACCESS_KEY}:${CATTLE_SECRET_KEY}" "https://$RANCHER_URL/v3/project/$RANCHER_PROJECT_ID/workloads/deployment:$NAME_SPACE:$updata_name"`
  #临时存储旧版本信息
  echo "$api_url" > /tmp/api_url.json
  #过滤获取旧版本信息
  images=`cat /tmp/api_url.json | jq ".containers|.[]|.image" | grep "$HARBOR_URL" | awk -F \: '{print $NF}' | cut -d \" -f 1 `
  #YAML文件版本更新
  sed -i s/$images/$CI_COMMIT_SHORT_SHA/g /home/cicd/$NAME_SPACE/yaml/"$updata_name".yaml
  #判断是否为新程序
  if [[ $images != "" ]]; then
#生成更新数据
echo "
curl -k -u "${CATTLE_ACCESS_KEY}:${CATTLE_SECRET_KEY}" \
-X PUT \
-H 'Accept: application/json' \
-H 'Content-Type: application/json' \
-d '$api_url' \
'https://$RANCHER_URL/v3/project/$RANCHER_PROJECT_ID/workloads/deployment:$NAME_SPACE:$updata_name'
" > /tmp/app_update.json
  #替换版本
  sed -i s/"$images"/"$CI_COMMIT_SHORT_SHA"/g /tmp/app_update.json
  #备份配配置文件
  echo "kubectl --kubeconfig /home/cicd/$NAME_SPACE/.kube/config get  configmap $updata_name  -n $NAME_SPACE -o yaml > /home/cicd/$NAME_SPACE/yaml/"$updata_name"_configmap_"$date".yaml"
  kubectl --kubeconfig /home/cicd/$NAME_SPACE/.kube/config get  configmap $updata_name  -n $NAME_SPACE -o yaml > /home/cicd/$NAME_SPACE/yaml/"$updata_name"_configmap_"$date".yaml
  #执行更新
  bash /tmp/app_update.json
  echo "$i 程序版本更新完毕，当前版本为: $CI_COMMIT_SHORT_SHA"
  else
    #创建部署程序
    echo "程序未部署,开始部署新程序$i"
   

  csproj=`find . -name $i.csproj`
  netcoreapp=`cat $csproj | egrep -oi netcoreapp`
  if  [[ $netcoreapp != "netcoreapp" ]]; then
    echo "无法获取该 $i 程序.netcore版本或非netcoreapp框架.跳出本次部署"
    continue
  fi 

    create_images="$HARBOR_URL\/$NAME_SPACE\/$updata_name"
    Development_file="$app_name_url/appsettings.Development.json"
    #获取urls端口
    Development_urls=`cat $Development_file | grep ListenHost | grep -Po "\d+"`

    #加载配置文件映射
    configMap=`kubectl --kubeconfig /home/cicd/$NAME_SPACE/.kube/config  get configmap -n $NAME_SPACE | grep $updata_name | wc -l`
    if [ $configMap == 0 ] && [  -f $Development_file ]; then
      echo "$i 配置文件存在 加载配置文件config文件,默认pod部署为Development为准"
      cp /home/cicd/$NAME_SPACE/Development-configs.yaml .
      sed -i s/app_name/$updata_name/g Development-configs.yaml
      sed -i s/name_space/$NAME_SPACE/g Development-configs.yaml
      cat $Development_file >> Development-configs.yaml
      sed -i '8,$s/^/    /g' Development-configs.yaml
      kubectl --kubeconfig /home/cicd/$NAME_SPACE/.kube/config apply -f Development-configs.yaml
    elif [ $configMap == 0 ] && [ ! -f $Development_file ]; then
      echo "警告!!! $i gitlab配置文件不存在退出部署"
      continue
    else
      echo "$i k8s配置映射存在，不重新生成加载gitlab配置文件"
      echo "备份配配置文件"
      kubectl --kubeconfig /home/cicd/$NAME_SPACE/.kube/config get  configmap $updata_name  -n $NAME_SPACE -o yaml > /home/cicd/$NAME_SPACE/yaml/"$updata_name"_configmap_"$date".yaml
    fi

    #判断端口是否存在
    #无端口部署
    if [[  $Development_urls == "" ]]; then #&& [  $Development_athena == "null" ]; then
      cp /home/cicd/$NAME_SPACE/node-noport.yaml .
      sed -i s/app_name/$updata_name/g node-noport.yaml
      sed -i s/name_space/$NAME_SPACE/g node-noport.yaml
      sed -i s/"images"/$create_images/g node-noport.yaml
      sed -i s/"create_version"/$CI_COMMIT_SHORT_SHA/g node-noport.yaml
      sed -i s/PullSecrets_NAME/$imagePullSecrets_NAME/g node-noport.yaml
      echo "确认程序无端口服务,程序版本为: $CI_COMMIT_SHORT_SHA"
      kubectl --kubeconfig /home/cicd/$NAME_SPACE/.kube/config  apply -f node-noport.yaml
      #存储yaml文件
      cp node-noport.yaml /home/cicd/$NAME_SPACE/yaml/"$updata_name".yaml
      continue

    #urls端口部署
    elif [[ $Development_urls != "" ]]; then 
      cp /home/cicd/$NAME_SPACE/node.yaml .
      sed -i s/app_name/$updata_name/g node.yaml
      sed -i s/name_space/$NAME_SPACE/g node.yaml
      sed -i s/"images"/$create_images/g node.yaml
      sed -i s/"create_version"/$CI_COMMIT_SHORT_SHA/g node.yaml
      sed -i s/app_port/$Development_urls/g node.yaml
      sed -i s/PullSecrets_NAME/$imagePullSecrets_NAME/g node.yaml
      echo "确认程序端口urls服务,程序版本为: $CI_COMMIT_SHORT_SHA"
      kubectl --kubeconfig /home/cicd/$NAME_SPACE/.kube/config apply -f node.yaml
      #存储yaml文件
      cp node.yaml /home/cicd/$NAME_SPACE/yaml/"$updata_name".yaml
      continue
    fi
  fi
done
#清空更新临时存储文件
rm -rf /cicd_tmp_data/*
