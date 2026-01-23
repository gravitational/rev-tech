#!/bin/bash

#Update following fields for your env
#INSTANCE_LIST- space separated list of instances as seen in AWS to update
#TMP_FILE_LOC - Location of temp file used to update the DNS record
#LOG_FILE - Location of log file to record udpates
#DNS_ZONE_NAME - name of hosted zone in route53

export INSTANCE_LIST="user-server02 user-server01 user-auth02"
export TMP_FILE_LOC="update_record.json"
export LOG_FILE="update-route53.log"
export DNS_ZONE_NAME="example.com"

#DNS Settings
export COMMENT="Update IP address on `date`"
export TYPE='A'
export TTL=300

#Create update logfile if not exist
if [ ! -f $LOG_FILE ];then
  touch $LOG_FILE
fi

#Create array of instance names to update
for i in $INSTANCE_LIST
do 
#Get Public Address from instance
AWS_INST_PUB_IP=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=$i" --output text --query 'Reservations[*].Instances[*].PublicIpAddress')

#Get Hosted Domain ID by name
AWS_HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name $DNS_ZONE_NAME --output text --query 'HostedZones[0].Id')

#RECORDSET assumes DNS name matches instance name. If different recordset variable needs adjustment.
RECORDSET=$i"."$DNS_ZONE_NAME
TMP_FILE=$(mktemp $TMP_FILE_LOC)
    cat > ${TMP_FILE} << EOF
    {
      "Comment":"$COMMENT",
      "Changes":[
        {
          "Action":"UPSERT",
          "ResourceRecordSet":{
            "ResourceRecords":[
              {
                "Value":"$AWS_INST_PUB_IP"
              }
            ],
            "Name":"$RECORDSET",
            "Type":"$TYPE",
            "TTL":$TTL
          }
        }
      ]
    }
EOF

#Update each IP change and log update
aws route53 change-resource-record-sets --hosted-zone-id $AWS_HOSTED_ZONE_ID --change-batch file://$TMP_FILE_LOC >> $LOG_FILE
#Cleanup
rm $TMP_FILE_LOC

#verbose output for each update
echo $i " IP:"$AWS_INST_PUB_IP
done
