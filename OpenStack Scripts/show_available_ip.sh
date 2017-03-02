# Script taken from https://bugs.launchpad.net/neutron/+bug/1526587/comments/2

#!/bin/bash

SUBNET_NAME=$1
start_point=$(neutron subnet-show $SUBNET_NAME | grep allocation_pools | cut -d"|" -f3 | cut -d":" -f2| cut -d"\"" -f2| cut -d"." -f4)
ip_prefix=$(neutron subnet-show $SUBNET_NAME | grep allocation_pools | cut -d"|" -f3 | cut -d":" -f2| cut -d"\"" -f2| cut -d"." -f1-3)
end_point=$(neutron subnet-show $SUBNET_NAME | grep allocation_pools | cut -d"|" -f3 | cut -d":" -f3| cut -d"\"" -f2| cut -d"." -f4)
ip_list=$(neutron port-list | grep `neutron subnet-show $SUBNET_NAME | awk '/ id / {print $4}'` | cut -d"|" -f5 | cut -d":" -f3 | cut -d"\"" -f2| sort)

total_count=0
for((index=$start_point; index<$end_point;index++))
do
        ip=$ip_prefix"."$index
        result=$(echo $ip_list | grep $ip)

        if [[ -z $result ]]; then
                echo $ip
                let total_count++
        fi
done
echo "Total Count: "$total_count