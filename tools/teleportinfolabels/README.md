# teleportinfolabels
Scripts and howtos for providing resource information and with easily identifable colors. You can call a program or script program as part of the Teleport label configuration.  In addition to regular text you can also display unicode chars that include visually capturing colors like 🟡 🟢 ❌.   Please check out these examples and offer any feedback!

Example:
![image](https://user-images.githubusercontent.com/60704961/153775157-e6dac8dd-e92f-4286-8fd0-3e0581e70616.png)


WARNING: Confirm any of these scripts prior to use. All of them should be non-impactful. If you configure with a low period level that may cause additional overhead on the machine.



## Node Information
Example:
![image](https://user-images.githubusercontent.com/60704961/153775328-a3fba7fd-61c0-4ba1-bae9-216e04ce61ac.png)


Script files:
- `getnodeinfo.sh`
- `getfreemem.sh`
- `getfreespace.sh`

Example `getnodeinfo.sh` output that combines the `getfreemem.sh` and `getfreespace.sh` output.
stats: 25% mem 🟢 54% storage 🟡

To install:
1. Retrieve this repository
2. Add `getnodeinfo.sh`, `getfreemem.sh`, `getfreespace.sh` to user running Teleport's path or 
   copy to `/usr/local/bin`
3. Confirm output running
```bash
getnodeinfo.sh
```


```yaml
ssh_service:
  enabled: yes
  labels:
    env: prod
  commands:
  - command:
    - getnodeinfo.sh
    name: stats
    period: 1m
```

## Database Information
Uses a script to confirm port for database or application 

Example DB:
```bash
$ tsh db ls
Name              Description                    Labels                          Connect 
----------------- ------------------------------ ------------------------------- ------- 
dev-mysql-db      🐬 dev database                 status=Ok 🟢,tier=dev                    
dev-mysql2        🐬 Example self hosted mysql    status=Unavailable ❌,tier=dev           
dev-postgresql-db 🐘 dev database                 status=Ok 🟢,tier=dev 
```

Example App:
Confirms 
![image](https://user-images.githubusercontent.com/60704961/153775477-07514150-07bd-4cba-b8d4-2845154aab2e.png)


Script files:
- `getavail.sh`

`getavail.sh` takes the host and port number for the service to confirm is `open`

Calls nmap to check for available service with given service type
Usage: getavail.sh getavail.sh <HOST> <PORT> <service type to confirm : mysql> <output map output --outputnmap>

To install:
1. Retrieve this repository
2. Install `nmap` if not already available
3. Add `getavail.sh` to user PATH running Teleport path or 
   copy to `/usr/local/bin`
4. Confirm output running
```bash
# getavail.sh <database or web resource host> <port>
# Confirming if a port is open
getavail.sh www.example.com 443
Ok 🟢

#Now check against a port we don't expect to be available
```bash
getavail.sh www.example.com 444
Unavailable ❌
```

### Example database label 
   
```yaml
 - name: "postgresql-db"
   description: "🐘 postgresql database"
   protocol: "postgres"
   uri: "sample-rds-postgres-database-1.daf.us-east-1.rds.amazonaws.com:5432"
   aws:
     region: "us-east-1"
   static_labels:
     env: dev
   dynamic_labels:
   - name: "status"
     command:
       - getavail.sh
       - sam-rds-postgres-database-1.cmzxvtskm1qh.us-east-1.rds.amazonaws.com
       - 5432
       - postgresql
     period: 15m
```
   
## Example app resource example
 
   Example
   ```bash
   tsh apps ls
Application       Description Public Address                                Labels                                          
----------------- ----------- --------------------------------------------- ----------------------------------------------- 
jenkinsapp                    jenkinsapp.teleport.example.com        status=Ok 🟢, teleport.dev/origin=config-file
   ```
   
 Configure your service like below. 
   
```yaml
  - name: "jenkinsapp"
    uri: "http://localhost:8888"
    commands:
    - name: "status"
      command:
        - getavail.sh
        - localhost
        - 8888
      period: 5m
 ```



