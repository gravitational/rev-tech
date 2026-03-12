#Update DNS hosted zones
Automate Update AWS instances pub ip in Route53 hosted zones

##Update following fields for your env
INSTANCE_LIST- space separated list of instances as seen in AWS to update
TMP_FILE_LOC - Location of temp file used to update the DNS record
LOG_FILE - Location of log file to record udpates
DNS_ZONE_NAME - name of hosted zone in route53