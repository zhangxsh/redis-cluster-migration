#!/bin/bash
#################################################################
#### @Author: xianshuangzhang                                   #
#### @Date:   2020-08-06 12:24:48                               #
#### usage:  sh redis.sh                                                   #
#### any questions,please mail to:xianshuangzhang@gmail.com #
#################################################################

#please set the keys prefix which to be moved
keys="fortune* *many_more_keys*"

#the original redis cluster connection info
src_cluster_nodes="10.141.17.68:6379 10.141.17.68:6389 10.141.17.68:6399"
src_cluster_passwd="redisclusternew"

#the destination redis cluster connection info
dest_cluster_nodes="10.141.19.36:6379 10.141.19.36:6389 10.141.19.36:6399 10.141.19.36:7379 10.141.19.36:7389 10.141.19.36:7399"
dest_cluster_passwd="perftest"

global_node_info=

#to find the destination redis node,accroding the moved instructions
function destClusterNode(){
    
	all_nodes=(${dest_cluster_nodes})
	node_info=($(echo ${all_nodes[0]}|awk -F ":" '{print $1,$2}'))
	response=$(redis-cli -h ${node_info[0]} -p ${node_info[1]} -a $dest_cluster_passwd --no-auth-warning exists "$1"|awk '{print $0}')

	if [[ "$response" == "0" ]]
	then
		echo "dest node found :["${all_nodes[0]}"],key:["$1"]"
		global_node_info=${all_nodes[0]}
	elif [[ "$response" == "1" ]]
	then
		global_node_info="skip"
		echo "dest key first key exists skipped:["$1"]"
	elif [[ ${#response} -gt 6 && ${response:0:5} == "MOVED" ]]
	then
		global_node_info=`echo $response|awk '{print $3}'`
		echo "dest node founded!["$global_node_info"]"
	else
		global_node_info=${all_nodes[0]}

	fi

}

#using scan command to find all of the keys,avoid redis connection blocking
function funScanKeys(){
	redis-cli -h "$1" -p "$2" -a $3 --no-auth-warning SCAN $4 match "$5" count 100 |while read key
	m_host=$1
	m_port=$2
	do
		global_node_info="skip"
		if [[ -z $key ]]
		then
			break
		fi

		isnumber=`echo "$key" |sed 's/\.//g'|sed 's/-//g' | grep [^0-9] >/dev/null`
		if [[ -z "$key" ||  -z $(echo $key|sed 's/\.//g'|sed 's/-//g' | grep [^0-9]) ]] 
		then
			echo 1 >/dev/null
		else
			resp_redis=$(redis-cli -h "$1" -p "$2" -a $3 --no-auth-warning --raw dump "$key"|awk '{print $0}')
			if [[ ${#resp_redis} -gt 6 && ${resp_redis:0:5} == "MOVED" ]]
			then
				#find the src node info,when moved
				moved_host_port=($(echo $resp_redis|awk -F "[ :]" '{print $3,$4}'))
				m_host=${moved_host_port[0]}
				m_port=${moved_host_port[1]}
				echo "src node found:"$m_host":"$m_port
                
			fi
			destClusterNode $key

			if [[ $global_node_info != "skip" && ! -z $global_node_info ]]
			then

				dest_node_info=($(echo $global_node_info|awk -F ":" '{print $1,$2}'))
				double_check_resp=$(redis-cli -h ${dest_node_info[0]} -p ${dest_node_info[1]} --no-auth-warning -a $dest_cluster_passwd exists "$key")
				if [[ "$double_check_resp" == "0"  ]]
				then
					trans_resp=$(redis-cli -h $m_host -p $m_port -a $src_cluster_passwd --no-auth-warning --raw dump "$key" | perl -pe 'chomp if eof' | redis-cli -h ${dest_node_info[0]} -p ${dest_node_info[1]} --no-auth-warning -a $dest_cluster_passwd -x restore "$key" 0)
					echo "transf:"$trans_resp",from:"$m_host":"$m_port",to:"${dest_node_info[0]}":"${dest_node_info[1]}",key:["$key"]"
			    else
			    	echo "key double check exists,skipped:["$key"]"
			    fi
			fi
			
		fi
		
	done
}

function funKeyHandler(){
	for node in ${src_cluster_nodes}
	do
		port=${node#*:}
		host=${node%%:*}
		ended="false"
		start_index=0

		funScanKeys ${host} $port $src_cluster_passwd ${start_index} $1

		while [[ $ended == "false" ]]
		do
			line_text=`redis-cli -h "${host}" -p "$port" --no-auth-warning -a $src_cluster_passwd SCAN ${start_index} match "$1" count 100 |awk '{if($1!=""){print $1}}'`
			start_index=`echo $line_text|awk '{print $1}'`

			if [[ -z "$start_index" || "$start_index" -eq "0" ]] 
			then
				ended="true"
			else
				funScanKeys ${host} $port $src_cluster_passwd ${start_index} $1
			fi
		done
		
	done
}

function begin(){
	for key in $keys
	do
		funKeyHandler $key
	done
}

#the main method
begin



