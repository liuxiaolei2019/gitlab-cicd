#!/bin/bash
#最新提交更新模块
branch="develop"
app_sln_url=`find . -name *.sln | awk -F / '{print $2}'`
updata_number=`git log origin/$branch --grep=".*cicd.*"  --pretty=format:"" --name-only  -1 |  grep -v "^$" | sed  s/"^"$app_sln_url"\///g"  | awk -F / '{print $1}' | uniq  `

cicd_if=`git log --pretty="%s" -2 | grep -v "Merge branch" | uniq | egrep .*cicd.* | wc -l`
if [[ $cicd_if == 0 ]];then
cicd_submit=`git log --pretty="%s" -2 | grep -v "Merge branch"`
echo "本次提交信息为 $cicd_submit 非cicd触发信息，退出"
exit 1
elif [[ $updata_number == "" ]];then
git log origin/$branch  --pretty=format:"" --name-only  -1
echo "获取修改文件为空"
exit 1
fi

set -e
echo "本次触发程序列表: 
$updata_number"
for updata in $updata_number
do
  updata_url=`find . -name $updata`
  nugetconfig="/home/DevopsTools/Config/nuget.config"
  csproj=`find . -name $updata.csproj | wc -l`

  csproj_url=`find . -name $updata.csproj`
  #netcoreapp=`cat $csproj_url | egrep -oi netcoreapp`
  netcoreapp=`cat app_service_list.js | grep $updata | wc -l`
  version=`cat $updata_url/$updata.csproj | grep netcoreapp | awk -F "netcoreapp" '{print $2}' | cut -d "<" -f 1`
  if  [[ $netcoreapp != 0 ]] && [[ $version != "" ]]; then
  echo "$csproj_url  $netcoreapp"
  else
    echo "1,$updata 程序在非部署程序列表名单中，请在app_service_list.js中添加该项目"
    echo "2,.netcore版本未提取到.跳出本次发布"
    continue
  fi

  if [ $csproj  != 0 ];then
    echo "$updata ok"
    cd $updata_url
    echo ".net-sdk版本为: $version"
    dotnet-$version restore $updata.csproj  --configfile=$nugetconfig
#    dotnet-$version sonarscanner begin /k:"LZ_net_core" /d:sonar.host.url="http://192.168.1.228:9000" /d:sonar.login="94c80a839cf8b09c9c46c94249f047087e821c72"
    dotnet-$version build $updata.csproj  -c Release -o ./app
#    dotnet-$version sonarscanner end /d:sonar.login="94c80a839cf8b09c9c46c94249f047087e821c72"
    dotnet-$version publish -c Release -o ./app
    echo "开始打包发布文件"
    #替换大小写
    updata_name=`echo "$updata" | sed s/"\."//g |  tr  A-Z a-z`
    echo "加载指定文件"
    cp -a ./configs/sync/* app/
    tar -zcf app.tar.gz app/*
    mkdir -p /cicd_tmp_data/$updata
    cp -a app/* /cicd_tmp_data/$updata
    #创建镜像
    docker build -t XXXXX.XXXXXX/$NAME_SPACE/$updata_name:$CI_COMMIT_SHORT_SHA .
    #推送镜像
    docker push XXXXX.XXXXXX/$NAME_SPACE/$updata_name:$CI_COMMIT_SHORT_SHA
    #删除本地镜像 
    docker rmi XXXXXX.XXXXXX/$NAME_SPACE/$updata_name:$CI_COMMIT_SHORT_SHA
    cd -
    echo "程序镜像地址: xxxxxx.xxxxxx/$NAME_SPACE/$updata_name:$CI_COMMIT_SHORT_SHA"
    else
    echo "error! $updata  未找到csproj项目文件"
  fi
done
