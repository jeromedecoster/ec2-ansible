.SILENT:

help:
	{ grep --extended-regexp '^[a-zA-Z0-9._-]+:.*#[[:space:]].*$$' $(MAKEFILE_LIST) || true; } \
	| awk 'BEGIN { FS = ":.*#[[:space:]]*" } { printf "\033[1;32m%-18s\033[0m%s\n", $$1, $$2 }'

ec2-create: # create load balancer + instances using autoscaling
	./make.sh ec2-create

load-balancer-dns: # get load balancer dns
	./make.sh load-balancer-dns

ansible-ping: # ping ec2 instances with ansible
	./make.sh ansible-ping

ansible-update: # update website on ec2 instances with ansible
	./make.sh ansible-update

destroy: # destroy all resources
	./make.sh destroy
