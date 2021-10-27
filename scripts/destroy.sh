set-auto-scaling-group-arn() {
    AUTO_SCALING_GROUP_ARN=$(aws autoscaling describe-auto-scaling-groups \
        --query "AutoScalingGroups[?AutoScalingGroupName=='$PROJECT_NAME'].AutoScalingGroupARN" \
        --region $AWS_REGION \
        --output text)
    log AUTO_SCALING_GROUP_ARN $AUTO_SCALING_GROUP_ARN
}

set-load-balancer-arn() {
    LOAD_BALANCER_ARN=$(aws elbv2 describe-load-balancers \
        --query "LoadBalancers[?LoadBalancerName=='$PROJECT_NAME'].LoadBalancerArn" \
        --region $AWS_REGION \
        --output text)
    log LOAD_BALANCER_ARN $LOAD_BALANCER_ARN
}

set-launch-template-id() {
    LAUNCH_TEMPLATE_ID=$(aws ec2 describe-launch-templates \
        --query "LaunchTemplates[?LaunchTemplateName=='$PROJECT_NAME'].LaunchTemplateId" \
        --region $AWS_REGION \
        --output text)
    log LAUNCH_TEMPLATE_ID $LAUNCH_TEMPLATE_ID
}

set-role-id() {
    ROLE_ID=$(aws iam list-roles \
        --query "Roles[?RoleName=='$PROJECT_NAME'].RoleId" \
        --region $AWS_REGION\
        --output text)
    log ROLE_ID $ROLE_ID
}

set-security-group-id() {
    SECURITY_GROUP_ID=$(aws ec2 describe-security-groups \
        --query "SecurityGroups[?GroupName=='$PROJECT_NAME'].GroupId" \
        --region $AWS_REGION \
        --output text)
    log SECURITY_GROUP_ID $SECURITY_GROUP_ID
}

set-key-pair-id() {
    KEY_PAIR_ID=$(aws ec2 describe-key-pairs \
        --query "KeyPairs[?KeyName=='$PROJECT_NAME'].KeyPairId" \
        --region $AWS_REGION \
        --output text)
    log KEY_PAIR_ID $KEY_PAIR_ID
}

delete-autoscaling() {
    set-auto-scaling-group-arn
    [[ -z "$AUTO_SCALING_GROUP_ARN" ]] && { warn skip "auto scaling group $PROJECT_NAME not found"; return; }

    aws autoscaling delete-auto-scaling-group \
        --auto-scaling-group-name $PROJECT_NAME \
        --force-delete

    echo ······ deleting auto-scaling-group. sleep 5 seconds ······
    sleep 5

    INSTANCE_IDS=$(aws autoscaling describe-auto-scaling-instances \
        --query "AutoScalingInstances[?AutoScalingGroupName=='$PROJECT_NAME'].InstanceId" \
        --region $AWS_REGION \
        --output text)

    # only calling `aws autoscaling delete-auto-scaling-group` is very very slow
    # try to accelerate by manually terminate instances too
    aws ec2 terminate-instances \
        --instance-ids $INSTANCE_IDS \
        --query "TerminatingInstances[].[InstanceId, CurrentState.Name]" \
        --region $AWS_REGION \
        --output text

    echo ······ terminating instances. sleep 5 seconds ······
    sleep 5

    while [[ -n $(aws autoscaling describe-auto-scaling-groups \
                --query "AutoScalingGroups[?AutoScalingGroupName=='$PROJECT_NAME'].Status" \
                --output text) ]]; do
        echo ······ waiting auto-scaling-group destruction. sleep 20 seconds ······
        sleep 20
    done

    # delete launch template silently
    set-launch-template-id
    aws ec2 delete-launch-template \
        --launch-template-id $LAUNCH_TEMPLATE_ID \
        --region $AWS_REGION \
        1>/dev/null \
        2>/dev/null
}

delete-load-balancer() {
    set-load-balancer-arn
    [[ -z "$LOAD_BALANCER_ARN" ]] && { warn skip "load balancer $PROJECT_NAME not found"; return; }

    aws elbv2 delete-load-balancer \
        --load-balancer-arn $LOAD_BALANCER_ARN
}

delete-ec2-role() {
    set-role-id
    [[ -z "$ROLE_ID" ]] && { warn skip "role $PROJECT_NAME not found"; return; }

    aws iam remove-role-from-instance-profile \
        --instance-profile-name $PROJECT_NAME \
        --role-name $PROJECT_NAME \
        2>/dev/null

    aws iam delete-instance-profile \
        --instance-profile-name $PROJECT_NAME \
        2>/dev/null

    aws iam detach-role-policy \
        --role-name $PROJECT_NAME \
        --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess \
        2>/dev/null
        
    aws iam delete-role \
        --role-name $PROJECT_NAME
}

delete-security-group() {
    set-security-group-id
    [[ -z "$SECURITY_GROUP_ID" ]] && { warn skip "security group $PROJECT_NAME not found"; return; }

    aws ec2 delete-security-group \
        --group-id $SECURITY_GROUP_ID \
        --region $AWS_REGION
}

delete-key-pair() {
    set-key-pair-id
    [[ -z "$KEY_PAIR_ID" ]] && { warn skip "key pair $PROJECT_NAME not found"; return; }

    aws ec2 delete-key-pair \
        --key-pair-id $KEY_PAIR_ID \
        --region $AWS_REGION

    rm --force $PROJECT_DIR/$PROJECT_NAME.pem
}

delete-autoscaling
delete-load-balancer
delete-ec2-role
delete-security-group
delete-key-pair