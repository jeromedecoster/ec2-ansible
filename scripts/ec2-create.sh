set-key-pair-id() {
    KEY_PAIR_ID=$(aws ec2 describe-key-pairs \
        --query "KeyPairs[?KeyName=='$PROJECT_NAME'].KeyPairId" \
        --region $AWS_REGION \
        --output text)
    log KEY_PAIR_ID $KEY_PAIR_ID
}

set-security-group-id() {
    SECURITY_GROUP_ID=$(aws ec2 describe-security-groups \
        --query "SecurityGroups[?GroupName=='$PROJECT_NAME'].GroupId" \
        --region $AWS_REGION \
        --output text)
    log SECURITY_GROUP_ID $SECURITY_GROUP_ID
}

set-role-id() {
    ROLE_ID=$(aws iam list-roles \
        --query "Roles[?RoleName=='$PROJECT_NAME'].RoleId" \
        --output text)
    log ROLE_ID $ROLE_ID
}

set-vpc-id() {
    # id of the default VPC
    VPC_ID=$(aws ec2 describe-vpcs \
        --query 'Vpcs[0].VpcId' \
        --filter 'Name=is-default,Values=true' \
        --region $AWS_REGION \
        --output text)
    log VPC_ID $VPC_ID
}

set-ami-id() {
    # get the current latest AMI id (Amazon Linux 2 AMI 64-bit x86)
    AMI_ID=$(aws ec2 describe-images \
        --region $AWS_REGION \
        --owners amazon \
        --query "reverse(sort_by(Images, &CreationDate))[:1].ImageId" \
        --filter 'Name=name,Values=amzn2-ami-hvm-2.0.*-x86_64-gp2' \
        --output text)
    log AMI_ID $AMI_ID
}

set-target-group-arn() {
    TARGET_GROUP_ARN=$(aws elbv2 describe-target-groups \
        --query "TargetGroups[?TargetGroupName=='$PROJECT_NAME'].TargetGroupArn" \
        --region $AWS_REGION \
        --output text)
    log TARGET_GROUP_ARN $TARGET_GROUP_ARN
}

set-launch-configuration-arn() {
    LAUNCH_CONFIGURATION_ARN=$(aws autoscaling describe-launch-configurations \
        --query "LaunchConfigurations[?LaunchConfigurationName=='$PROJECT_NAME'].LaunchConfigurationARN" \
        --output text)
    log LAUNCH_CONFIGURATION_ARN $LAUNCH_CONFIGURATION_ARN
}

set-instance-profile-arn() {
    INSTANCE_PROFILE_ARN=$(aws iam list-instance-profiles \
        --query "InstanceProfiles[?InstanceProfileName=='$PROJECT_NAME'].Arn" \
        --output text)
    log INSTANCE_PROFILE_ARN $INSTANCE_PROFILE_ARN
}

set-launch-template-id() {
    LAUNCH_TEMPLATE_ID=$(aws ec2 describe-launch-templates \
        --query "LaunchTemplates[?LaunchTemplateName=='$PROJECT_NAME'].LaunchTemplateId" \
        --region $AWS_REGION \
        --output text)
    log LAUNCH_TEMPLATE_ID $LAUNCH_TEMPLATE_ID
}

#
# create the $PROJECT_NAME RSA keypair and download $PROJECT_NAME.pem file
#
create-key-pair() {
    set-key-pair-id
    [[ -n "$KEY_PAIR_ID" ]] && { warn skip "keypair $PROJECT_NAME already exists"; return; }
    
    # create RSA key
    aws ec2 create-key-pair \
        --key-name $PROJECT_NAME \
        --query 'KeyMaterial' \
        --region $AWS_REGION \
        --output text > $PROJECT_DIR/$PROJECT_NAME.pem

    # chmod required before using ssh
    chmod 400 $PROJECT_DIR/$PROJECT_NAME.pem

    info created file $PROJECT_NAME.pem
}

create-security-group() {
    set-security-group-id
    [[ -n "$SECURITY_GROUP_ID" ]] && { warn skip "security group $PROJECT_NAME already exists"; return; }

    local DATETIME=$(date "+%Y-%d-%m %H:%M:%S")
    SECURITY_GROUP_ID=$(aws ec2 create-security-group \
        --group-name $PROJECT_NAME \
        --query GroupId \
        --description "$PROJECT_NAME created $DATETIME" \
        --region $AWS_REGION \
        --output text)
    log SECURITY_GROUP_ID $SECURITY_GROUP_ID

    # add the specified inbound (ingress) rules to the security group
    # use the --ip-permissions format because it's the ONLY WAY to allow Ipv6 '::/0' cidr
    # using --protocol, --port and --cidr options allow only Ipv4 '0.0.0.0/0' cidr
    aws ec2 authorize-security-group-ingress \
        --group-id $SECURITY_GROUP_ID \
        --ip-permissions IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges=[{CidrIp=0.0.0.0/0}] \
            IpProtocol=tcp,FromPort=22,ToPort=22,Ipv6Ranges=[{CidrIpv6=::/0}] \
        2>/dev/null

    # same for port 80
    aws ec2 authorize-security-group-ingress \
        --group-id $SECURITY_GROUP_ID \
        --ip-permissions IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges=[{CidrIp=0.0.0.0/0}] \
            IpProtocol=tcp,FromPort=80,ToPort=80,Ipv6Ranges=[{CidrIpv6=::/0}] \
        2>/dev/null

    # same for port 443
    aws ec2 authorize-security-group-ingress \
        --group-id $SECURITY_GROUP_ID \
        --ip-permissions IpProtocol=tcp,FromPort=443,ToPort=443,IpRanges=[{CidrIp=0.0.0.0/0}] \
            IpProtocol=tcp,FromPort=443,ToPort=443,Ipv6Ranges=[{CidrIpv6=::/0}] \
        2>/dev/null

    info created security group $PROJECT_NAME
}

create-ec2-role() {
    set-role-id
    [[ -n "$ROLE_ID" ]] && { warn skip "iam role $PROJECT_NAME already exists"; return; }

    local DATETIME=$(date "+%Y-%d-%m %H:%M:%S")
    ROLE_ID=$(aws iam create-role \
        --role-name $PROJECT_NAME \
        --assume-role-policy-document '{"Statement":{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}}' \
        --description "$PROJECT_NAME created $DATETIME" \
        --query 'Role.RoleId' \
        --region $AWS_REGION \
        --output text)
    log ROLE_ID $ROLE_ID

    # attach AmazonEC2FullAccess policy role
    aws iam attach-role-policy \
        --role-name $PROJECT_NAME \
        --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess

    # ec2 instances
    INSTANCE_PROFILE_ID=$(aws iam create-instance-profile \
        --instance-profile-name $PROJECT_NAME \
        --query 'InstanceProfile.InstanceProfileId' \
        --output text)
    log INSTANCE_PROFILE_ID $INSTANCE_PROFILE_ID

    aws iam add-role-to-instance-profile \
        --instance-profile-name $PROJECT_NAME \
        --role-name $PROJECT_NAME

    info created iam role $PROJECT_NAME
}

create-load-balancer() {
    set-vpc-id

    # create target group
    TARGET_GROUP_ARN=$(aws elbv2 create-target-group \
        --name $PROJECT_NAME \
        --query 'TargetGroups[].TargetGroupArn' \
        --protocol TCP \
        --port 80 \
        --vpc-id $VPC_ID \
        --region $AWS_REGION \
        --output text)
    log TARGET_GROUP_ARN $TARGET_GROUP_ARN

    # all VPC subnets (inline result, separated by space)
    SUBNETS_ID=$(aws ec2 describe-subnets \
        --filters Name=vpc-id,Values=$VPC_ID \
        --query 'Subnets[].SubnetId' \
        --region $AWS_REGION \
        --output text)
    log SUBNETS_ID $SUBNETS_ID

    LOAD_BALANCER_ARN=$(aws elbv2 create-load-balancer \
        --name $PROJECT_NAME \
        --type network \
        --subnets $SUBNETS_ID \
        --query 'LoadBalancers[].LoadBalancerArn' \
        --region $AWS_REGION \
        --output text)
    log LOAD_BALANCER_ARN $LOAD_BALANCER_ARN

    # create TCP listener (redirect to target group)
    LISTENER_ARN=$(aws elbv2 create-listener \
        --load-balancer-arn $LOAD_BALANCER_ARN \
        --protocol TCP \
        --port 80 \
        --default-actions Type=forward,TargetGroupArn=$TARGET_GROUP_ARN \
        --query 'Listeners[].ListenerArn' \
        --region $AWS_REGION \
        --output text)
    log LISTENER_ARN $LISTENER_ARN

    while [[ $(aws elbv2 describe-load-balancers \
                --query "LoadBalancers[?LoadBalancerName=='$PROJECT_NAME'].State.Code" \
                --output text) != 'active' ]]; do

        LOAD_BALANCER_STATUS=$(aws elbv2 describe-load-balancers \
            --query "LoadBalancers[?LoadBalancerName=='$PROJECT_NAME'].State.Code" \
            --output text)
        log LOAD_BALANCER_STATUS $LOAD_BALANCER_STATUS
        echo ······ waiting load-balancer creation. sleep 20 seconds ······
        sleep 20
    done
}

create-autoscaling() {
    set-instance-profile-arn
    set-ami-id
    set-target-group-arn
    set-security-group-id

    USER_DATA=$(cat $PROJECT_DIR/user-data.sh | base64 -w 0)
    log USER_DATA $USER_DATA

    cat > $PROJECT_DIR/launch-template.json << EOF
{
    "IamInstanceProfile": {
        "Arn": "${INSTANCE_PROFILE_ARN}"
    },
    "ImageId": "${AMI_ID}",
    "InstanceType": "t2.micro",
    "KeyName": "${PROJECT_NAME}",
    "UserData": "${USER_DATA}",
    "SecurityGroupIds": [
        "${SECURITY_GROUP_ID}"
    ]
}
EOF

    set-launch-template-id
    if [[ -z "$LAUNCH_TEMPLATE_ID" ]];
    then
        LAUNCH_TEMPLATE_ID=$(aws ec2 create-launch-template \
            --launch-template-name $PROJECT_NAME \
            --version-description $PROJECT_NAME-v1 \
            --launch-template-data file://$PROJECT_DIR/launch-template.json \
            --query 'LaunchTemplate.LaunchTemplateId' \
            --region $AWS_REGION \
            --output text)
        log LAUNCH_TEMPLATE_ID $LAUNCH_TEMPLATE_ID
    fi

    AVAILABILITY_ZONES=$(aws ec2 describe-availability-zones \
        --query 'AvailabilityZones[].ZoneName' \
        --region $AWS_REGION \
        --output text)
    log AVAILABILITY_ZONES $AVAILABILITY_ZONES
    
    aws autoscaling create-auto-scaling-group \
        --auto-scaling-group-name $PROJECT_NAME \
        --launch-template LaunchTemplateId=$LAUNCH_TEMPLATE_ID \
        --min-size 2 \
        --max-size 3 \
        --availability-zones $AVAILABILITY_ZONES \
        --target-group-arns $TARGET_GROUP_ARN \
        --health-check-type ELB \
        --health-check-grace-period 300 \
        --region $AWS_REGION
}

create-key-pair
create-security-group
create-ec2-role
create-load-balancer
set-instance-profile-arn
create-autoscaling
