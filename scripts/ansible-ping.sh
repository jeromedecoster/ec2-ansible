ansible-ping() {
    cd $PROJECT_DIR/playbooks
    ansible aws -m ping
}

ansible-ping
