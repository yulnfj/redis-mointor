#!/bin/bash

######变量定义####################################
auth="123"               #认证密码
configdir='/usr/local/redis-cluster/'          #配置目录
bindir='/usr/sbin/'            #redis安装目录
bindir1='/usr/bin/'            #redis安装目录
client="$bindir1/redis-cli -a $auth -c  " #通过密码登录redis集群 
max_memory=0                              #初始化最大内存
flag=0                                    #输入参数是否有误标识

list=(
192.168.192.138:8000
192.168.192.138:8001
192.168.192.131:8000
192.168.192.131:8001
192.168.192.132:8000
192.168.192.132:8001
)                                        #集群ip list

###redis状态统计函数###############################
statistics_redis(){
local ip=`echo $1 | awk -F':' '{print $1}'`
local port=`echo $1 | awk -F':' '{print $2}'`
local is_slowlog=0

last_slowlog_time=`$client -h $ip -p $port  2>>/dev/null slowlog get 1 |awk  '{if(NR==2) print $1}' `
current_time=`date +%s`

if [ "$last_slowlog_time" != "" ]; then
  if [ $((last_slowlog_time+60*10)) -gt $current_time ]; then
   is_slowlog=1
  fi
fi

#redis-cli -c -h 192.168.192.138 -p 8001 -a 123 info Replication | grep role | awk -F':' '{print $2}'
$client -h $ip -p $port info all 2>>/dev/null | awk -F ':' -v max_memory=$max_memory -v addr=$1 -v is_sendms=$2 -v is_slowlog=$is_slowlog '{\
if($0~/uptime_in_seconds:/) uptime=$2;\
else if($0~/connected_clients:/) cnt_clients=$2;\
else if($0~/role:/) role=$2;\
else if($0~/used_memory:/) used_memory=$2;\
else if($0~/used_memory_rss:/) used_memory_rss=$2;\
else if($0~/used_memory_peak:/) used_memory_peak=$2;\
else if($0~/mem_fragmentation_ratio:/) mem_ratio=$2;\

else if($0~/rdb_last_bgsave_status:/) bgsave_status=$2;\
else if($0~/aof_last_write_status:/) aof_write_status=$2;\
else if($0~/aof_last_bgrewrite_status:/) aof_bgrewrite_status=$2;\

else if($0~/instantaneous_ops_per_sec:/) ops_per_sec=$2;\
else if($0~/keyspace_hits:/) keyspace_hits=$2;\
else if($0~/keyspace_misses:/) keyspace_misses=$2;\
else if($0~/:keys=/) keys=keys"\n"$2;\

}END{\
printf("\033[1;33;1m####概况:\033[0m\n");\
printf("    启动时间:%d\n",uptime);\
printf("    当前连接数:%d\n",cnt_clients);\
printf("    当前OPS:%d\n",ops_per_sec);\
printf("    当前key分布情况:%s\n",keys);\
printf("    当前角色:%s\n",role);\

printf("\033[1;33;1m####命中情况：\033[0m\n");\
printf("    命中次数: %d\n",keyspace_hits);\
printf("    miss次数: %d\n",keyspace_misses);\
printf("    命中率：%d%\n",keyspace_hits/(keyspace_hits+keyspace_misses+0.1)*100);\

printf("\033[1;33;1m####内存使用情况：\033[0m\n");\
printf("    1)分配总内存:%dMb\n",used_memory_rss/1024/1024);\
printf("    2)使用内存:%dMb\n",used_memory/1024/1024);\
printf("    3)峰值:%dMb\n",used_memory_peak/1024/1024);\
printf("    4)最大内存:%dMb\n",max_memory/1024/1024);\
printf("    5)内存碎片率:%s\n",mem_ratio);\

printf("\033[1;33;1m####持久化: \033[0m\n");\
printf("    上次bgsave状态:%s\n",bgsave_status);\
printf("    上次aof状态:%s\n",aof_write_status);\
printf("    上次rewrite状态:%s\n",aof_bgrewrite_status);\

printf("\033[1;33;1m####报警信息: \033[0m\n");\
if(cnt_clients>=1000){printf("\033[1;31;1mwarning: 当前连接数:%d,超标\033[0m\n",cnt_clients);\
                      system("sendms "addr"_当前连接数:"cnt_clients" "is_sendms);\
                      };\
if(ops_per_sec>=50000){printf("\033[1;31;1mwarning: 当前OPS:%d,超标\033[0m\n",ops_per_sec);\
                       system("sendms "addr"_当前OPS:"ops_per_sec" "is_sendms);\
                      };\

if(keyspace_hits/(keyspace_hits+keyspace_misses+0.1)*100<=50){\
                  printf("\033[1;31;1mwarning:当前命中率：%d%,过低\033[0m\n",keyspace_hits/(keyspace_hits+keyspace_misses+0.1)*100);\
                 };\

if(used_memory/max_memory*100>=80){printf("\033[1;31;1mwarning:当前内存使用：%d%,过高\033[0m\n",used_memory/max_memory*100);\
                                   system("sendms "addr"_内存使用率:"used_memory/max_memory*100"% "is_sendms);\
                                  };\

if(is_slowlog>0) {printf("\033[1;31;1mwarning：存在慢查询，请确认!\033[0m\n");\
                    system("sendms "addr"_存在慢查询 "is_sendms) };\

#if(bgsave_status!~/ok/){printf("上次bgsave状态错误:%s\n",bgsave_status)};\
#if(aof_write_status!~/ok/){printf("上次aof状态错误:%s\n",aof_write_status)};\
#if (aof_bgrewrite_status!~/ok/){printf("上次rewrite状态错误:%s\n",aof_bgrewrite_status)};\
} ' 2>>/dev/null 


}
###############################################

####BEGIN:遍历list##################
for config in ${list[@]}
do
   ip=`echo $config| awk -F':' '{print $1}'`
   port=`echo $config| awk -F':' '{print $2}'`

####stop######################
   if [ "$1" == "stop" ]; then
      flag=1
      echo -n $config" "
      `$client -h $ip -p $port shutdown 2>>/dev/null`
      #if [ $? -eq 0 ]; then
         echo "shutdown success!"
      #else
      #   echo "shutdown meet error!"
      #fi
   fi

####start###################
   if [ "$1" == "start" ]; then
      flag=1
      echo -n  $config" "
      ssh $ip "${bindir}/redis-server  ${configdir}/redis${port}.conf"
      if [ $? -eq 0 ]; then
         echo "started"
      else
        echo "starting meet error"
      fi
   fi

####ps##################
   if [ "$1" == "ps" ]; then
      flag=1
      ssh $ip "netstat -ntpl | grep $ip:$port"
      num=`ssh $ip "netstat -ntpl | grep $ip:$port" |wc -l`
      if [ $num -eq 0 ]; then
         echo -e "\e[1;32;1m$ip:$port 没有启动redis服务\e[0m"
      fi
   fi

####status##################
   if [ "$1" == "status" ]; then
      flag=1
      ###找到一个存活的节点，根据它来查看集群状态
      isalive=`$client -c -h $ip -p $port ping 2>>/dev/null`
      if [ "$isalive" == "PONG" ]; then
         echo -e "\e[1;32;1m#----------------------------------#\e[0m"
         echo -e "\e[1;32;1m#集群基本信息:                     #\e[0m"
         echo -e "\e[1;32;1m#----------------------------------#\e[0m"
         cluster_is_ok=`$client -c -h $ip -p $port cluster info 2>>/dev/null | grep cluster_state| cut -b 15-16` 
         if [ "$cluster_is_ok" == "ok" ]; then
             echo -e "cluster_state:\e[1;32;1mok\e[0m"
         else
             echo -e "\033[1;31;1m$($client  -h $ip -p $port 2>>/dev/null cluster info | grep cluster_state)\e[0m"
             sendms "${config}_cluster_state:$cluster_is_ok" $is_sendms
         fi
         nodes_alive=`$client -h ${ip}  -p ${port}  cluster nodes 2>>/dev/null | grep -vE 'fail|disconnected' | wc -l`
        
         if [ ${#list[*]} -ne $nodes_alive ]; then
            echo -e "total nodes:${#list[*]}, \033[1;31;1malive nodes:${nodes_alive}!!\033[0m"
            echo -e "\033[1;31;1mWarning: some nodes have down!!\033[0m"
            sendms "${config}_cluster_state:some_nodes_is_down" $is_sendms
         else
            echo "total nodes:${#list[*]}, alive nodes:${nodes_alive}"
         fi
         
         max_memory=`$client -h $ip -p $port 2>>/dev/null config get maxmemory | awk '{if(NR>1)print $1}'`
         ###使用循环匹配整理出目前cluster的M-s关系树
         echo -e "\e[1;32;4m#####主从结构树:\e[0m"

         v_str=""
         cnt=1
         for master in `$client -h $ip -p $port 2>>/dev/null cluster nodes|grep 'master'|grep -vE 'fail|disconnected'|awk '{print $1","$2}'|sort -k 2,2 -t ','`
         do
           mid=`echo $master | awk -F',' '{print $1}'`
           maddr=`echo $master | awk -F',' '{print $2}'`
           mip=`echo $master | awk -F',|:' '{print $2}'`
           echo -e  "\033[1;36;1mmaster${cnt}:"$maddr"\033[0m"
           $client -h $ip  -p $port 2>>/dev/null cluster nodes | grep 'slave'|grep -vE 'fail|disconnected' | grep $mid | awk '{print "|-->slave"NR":"$2} ' 
           tmp=`$client -h $ip -p $port cluster nodes 2>>/dev/null | grep  'slave'|grep -vE 'fail|disconnected'  | grep $mid | grep $mip | wc -l`
           v_tmp=`$client -h $ip  -p $port cluster nodes 2>>/dev/null | grep 'slave'|grep -vE 'fail|disconnected' | grep $mid | awk '{printf $2" "}' `

          if [ $tmp -ne 0 ]; then
             echo -e "\033[1;31;1mWarning: master's slave node is on the master's server!!\033[0m"
             sendms "${maddr}_cluster_state:M-S_is_on_same_server" $is_sendms 
          fi

           v_str=$v_str"\""$maddr" "$v_tmp"\" " 
           let cnt++
         done
         
         ###v_str变量记录("m1 s1" "m2 s2")类似的二维数组结构用于逐个分析每个存活状态的redis实例
         declare -a array="("$v_str")"

         ###使用双层嵌套循环遍历收集各个redis实例的状态
         n_array=${#array[*]}
         for((i=0; i<$n_array;i++))
         do
           inner_array=(${array[$i]})
           n_inner_array=${#inner_array[*]}
           echo ""
           echo -e  "\e[1;32;1m#----------------------------------#\e[0m"
           echo -e  "\e[1;32;1m#分片$((i+1)):                            #\e[0m"
           echo -e  "\e[1;32;1m#----------------------------------#\e[0m"
           for((j=0;j<$n_inner_array;j++))
           do
             echo -e "\e[1;35;1m+++++${inner_array[$j]}+++++\e[0m"
             statistics_redis ${inner_array[$j]} $is_sendms
           done
         done

         exit 0
      fi
   fi
done 

if [ "$flag" == "0" ]; then
  echo -e  "\e[1;31;1musage: sh cluster_control [start|stop|status|ps]\e[0m"
fi

if [ "$is_alive" != "PONG" -a "$1" == "status" ]; then
echo -e "\e[1;31;1mAll nodes is stopped.\e[0m"
fi
