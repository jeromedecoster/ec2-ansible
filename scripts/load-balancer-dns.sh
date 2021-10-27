load-balancer-dns() {
    LOAD_BALANCER_DNS_NAME=$(aws elbv2 describe-load-balancers \
        --query "LoadBalancers[?LoadBalancerName=='$PROJECT_NAME'].DNSName" \
        --region $AWS_REGION \
        --output text)
    log LOAD_BALANCER_DNS_NAME $LOAD_BALANCER_DNS_NAME
}

load-balancer-dns