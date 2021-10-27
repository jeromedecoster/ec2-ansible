#!/bin/bash
ID=$(aws autoscaling describe-auto-scaling-instances \
    --query "AutoScalingInstances[?AutoScalingGroupName=='ec2-ansible'].InstanceId" \
    --output text)
IP=$(aws ec2 describe-instances \
    --instance-ids $ID \
    --query "Reservations[].Instances[?State.Name=='running'].[InstanceId, PublicIpAddress]" \
    --output text)
    
if [[ -z "$IP" ]]; 
then
    cat << EOF
{
    "_meta": { "hostvars": {} },
    "aws": { "hosts": [] }
}
EOF
exit 0
fi

HOSTSVARS=
HOSTS=
while read h; do
    id=$(echo "$h" | cut -f 1)
    ip=$(echo "$h" | cut -f 2)
    TMP=$(echo '"'$id'": { "ansible_host": "'$ip'" },')
    HOSTSVARS=${HOSTSVARS}${TMP}
    TMP=$(echo '"'$id'",')
    HOSTS=${HOSTS}${TMP}
done < <(echo "$IP")

cat << EOF
{
    "_meta": {
        "hostvars": {
            ${HOSTSVARS}
        }
    },
    "aws": {
        "hosts": [
            ${HOSTS}
        ]
    }
}
EOF
