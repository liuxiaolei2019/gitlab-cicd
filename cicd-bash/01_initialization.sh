#!/bin/bash
branch="develop"
git remote add origin/$branch $git_remote_url

git remote -v
git branch -f $branch HEAD
git checkout $branch
git pull  origin/$branch

#csproj初始化
#date=`date`
sln_url=`find . -name *.sln`
app_name=`cat $sln_url | grep csproj |  awk '{print $3}' | cut -d \" -f 2`
#echo "init_time $date" > app_name.txt
for i in $app_name
do
csproj_url=`find . -name $i.csproj`
  #定位csproj路径
  for url in $csproj_url
  do
    #判断是否存在ProjectGuid字段
    url_output=`cat  $url | grep ProjectGuid | wc -l`
    if [ $url_output == 0  ];then
    echo "------------------------------------------------------------"
    echo "发现$url未添加ProjectGuid字段，进行自动添加"
    line=`grep -rn "<PropertyGroup>"  $url | awk -F ":"  '{print $1}'`
    #添加ProjectGuid字段+1
    line_1=$(($line+1))
    parameter=`cat $sln_url | grep $i.csproj | awk -F \"  '{print  $(NF -1)}'`
    sed -i "$line_1 i\    \<ProjectGuid\>$parameter\<\/ProjectGuid\> " $url
    else
    echo "-------------------------------------------------------------
    $url csproj ok"
    fi

    #定义net环境版本
    Version=`cat  $url  | grep netcoreapp | awk -F "netcoreapp" '{print $2}' | cut -d "<" -f 1`
    #获取当前程序名路径
    app_name_url=`find . -name $i`
    if [[ "$Version" != " " ]];then
    echo "$i 版本为$Version"
    cat >$app_name_url/Dockerfile <<EOF
#更具自身需要选择对应语言环境底层
FROM   XXXXX.XXXXX:$Version
ENV TZ=Asia/Shanghai
ENV ASPNETCORE_ENVIRONMENT=Development
ADD app.tar.gz opt/
WORKDIR /opt/app
ENTRYPOINT ["dotnet","$i.dll"]
EOF
    if [ ! -f app_service_list.js ] ;then
    echo "app_service_list.js 文件不存在创建文件"
    cat > app_service_list.js <<EOF
    #本文件用于说明该程序是否需要进行部署发布
EOF
    fi

    echo "添加sync目录"
    echo "$app_name_url/configs/sync"
    mkdir -p $app_name_url/configs/sync
    cat >$app_name_url/configs/sync/explain.txt  <<EOF
#该目录为加载文件目录(暂不支持压缩包)
EOF
    else
    echo "$i 版本为空"
    fi
    echo "app_name $i"
  done
done


git add .
git commit -m "#CI 初始化"
git push -f origin/$branch
