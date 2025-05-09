#!/bin/bash

set -ex

env

[ ! -d /git/system-config ] && git init --bare /git/system-config

cd /tmp
[ -d /tmp/system-config ] && rm -Rf /tmp/system-config
git clone /git/system-config
cd /tmp/system-config

git config user.name "sf-operator"
git config user.email "admin@${FQDN}"

mkdir -p zuul.d playbooks/base playbooks/config

cat << EOF > zuul.d/jobs-base.yaml
# Semaphores
# JobsBase

EOF

if [ -n "${CONFIG_REPO_NAME}" ]; then
  cat << EOF > zuul.d/config-project.yaml
---
# Pipelines
# Projects

EOF
else
  cat  << EOF > zuul.d/config-project.yaml
---
[]
EOF
fi

cat << EOF > playbooks/base/pre.yaml
- hosts: localhost
  tasks:
    - block:
        - import_role:
            name: emit-job-header
        - import_role:
            name: log-inventory
      vars:
        zuul_log_url: "https://${FQDN}/logs"

- hosts: all
  tasks:
    - include_role: name=start-zuul-console
    - block:
        - include_role: name=validate-host
        - include_role: name=prepare-workspace
        - include_role: name=add-build-sshkey
      when: "ansible_connection != 'kubectl'"
    - block:
        - include_role: name=prepare-workspace-openshift
        - include_role: name=remove-zuul-sshkey
      run_once: true
      when: "ansible_connection == 'kubectl'"
    - import_role: name=ensure-output-dirs
      when: ansible_user_dir is defined
EOF

cat << EOF > playbooks/base/post.yaml
- hosts: localhost
  roles:
    -  role: add-fileserver
       fileserver: "{{ site_sflogs }}"
    -  role: generate-zuul-manifest
  tasks:
    - when: not zuul_success | bool
      include_role:
        name: report-logjuicer
      vars:
        logjuicer_web_url: https://${FQDN}/logjuicer
        zuul_web_url: https://${FQDN}/zuul/t/{{ zuul.tenant }}

- hosts: ${ZUUL_LOGSERVER_HOST}
  gather_facts: false
  tasks:
    - block:
        - import_role:
            name: upload-logs
        - import_role:
            name: buildset-artifacts-location
      vars:
        zuul_log_compress: true
        zuul_log_url: "https://${FQDN}/logs"
        zuul_logserver_root: "{{ site_sflogs.path }}"
        zuul_log_verbose: true
EOF

cat << EOF > playbooks/config/zuul-connections.txt
# ZUUL_CONNECTIONS
EOF

cat << EOF > playbooks/config/check.yaml
- hosts: localhost
  vars:
    config_root: "{{ zuul.executor.work_root }}/{{ zuul.project.src_dir }}"
    zuul_config: "{{ config_root }}/zuul/main.yaml"
    zuul_connections: "{{ lookup('file', 'zuul-connections.txt') }}"
    nodepool_launcher_config: "{{ config_root }}/nodepool/nodepool.yaml"
    nodepool_builder_config: "{{ config_root }}/nodepool/nodepool-builder.yaml"
  tasks:
    - name: Ensure Zuul tenant config exists
      shell: |
        if ! test -f "{{ zuul_config }}"; then
          mkdir -p "{{ config_root }}/zuul/"
          echo [] > "{{ zuul_config }}"
        fi

    - name: Setup Zuul config.conf file
      ansible.builtin.copy:
        dest: "{{ zuul_config }}.conf"
        content: |
          {{ zuul_connections }}

          [scheduler]
          tenant_config={{ zuul_config }}

    - name: Reveal computed config
      ansible.builtin.command: cat {{ zuul_config }}.conf

    - name: Validate Zuul tenant config
      # note: ansible appears to be messing with the env, resulting in:
      #  ModuleNotFoundError: No module named 'zuul.cmd'
      # clearing the env fixes that issue.
      command: env - PATH=/usr/local/bin:/bin zuul-admin -c "{{ zuul_config }}.conf" tenant-conf-check

    - name: Ensure Nodepool launcher config exists
      shell: |
        if ! test -f "{{ nodepool_launcher_config }}"; then
          mkdir -p "{{ config_root }}/nodepool/"
          echo {} > "{{ nodepool_launcher_config }}"
        fi

    - name: Validate Nodepool launcher config
      command: env - PATH=/usr/local/bin:/bin nodepool -c "{{ nodepool_launcher_config }}" config-validate

    - name: Ensure Nodepool builder config exists
      shell: |
        if ! test -f "{{ nodepool_builder_config }}"; then
          mkdir -p "{{ config_root }}/nodepool/"
          echo {} > "{{ nodepool_builder_config }}"
        fi

    - name: Validate Nodepool builder config
      command: env - PATH=/usr/local/bin:/bin nodepool -c "{{ nodepool_builder_config }}" config-validate
EOF

cat << EOF > playbooks/config/update.yaml
---
- hosts: localhost
  roles:
    - setup-k8s-config
    - add-k8s-hosts

- hosts: zuul-scheduler
  vars:
    config_ref: "{{ zuul.newrev | default('origin/master') }}"
  tasks:
    - name: "Update zuul tenant config"
      command: /usr/local/bin/generate-zuul-tenant-yaml.sh "{{ config_ref }}"
    - name: "Reconfigure the scheduler"
      command: zuul-scheduler full-reconfigure

- hosts: nodepool-launcher
  vars:
    config_ref: "{{ zuul.newrev | default('origin/master') }}"
    ansible_python_interpreter: /usr/bin/python3.11
  tasks:
    - name: "Update nodepool-launcher config"
      command: /usr/local/bin/generate-config.sh "{{ config_ref }}"

- hosts: nodepool-builder
  vars:
    config_ref: "{{ zuul.newrev | default('origin/master') }}"
    ansible_python_interpreter: /usr/bin/python3.11
  tasks:
    - name: "Update nodepool-builder config"
      command: /usr/local/bin/generate-config.sh "{{ config_ref }}"
      environment:
        NODEPOOL_CONFIG_FILE: nodepool-builder.yaml

# Handle code-search config-update tasks
# The StatefulSet controller will restart the pod after the deletion
# Ideally we should run a rollout restart but kubectl does not have that capability, or better, run the hound config update script in-place but hound does not support hot reload.
- hosts: localhost
  tasks:
    - name: Check if hound-search pod is running
      command: kubectl get pod hound-search-0
      register: houndsearch_pod_get
      ignore_errors: true
    - name: Force hound-search restart by deleting the pod
      command: kubectl delete pod hound-search-0
      when: houndsearch_pod_get.rc == 0

EOF

mkdir -p roles/add-k8s-hosts/tasks
cat << EOF > roles/add-k8s-hosts/tasks/main.yaml
---
- ansible.builtin.add_host:
    name: "zuul-scheduler"
    ansible_connection: kubectl
    ansible_kubectl_container: zuul-scheduler
    ansible_kubectl_pod: "zuul-scheduler-0"

- name: Fetch nodepool-launcher Pod info
  command: "kubectl get pod -o=custom-columns=NAME:.metadata.name --no-headers --selector=run=nodepool-launcher"
  register: nodepool_launcher_info

- ansible.builtin.add_host:
    name: "nodepool-launcher"
    ansible_connection: kubectl
    ansible_kubectl_pod: "{{ nodepool_launcher_info.stdout }}"
    ansible_kubectl_container: launcher

- ansible.builtin.add_host:
    name: "nodepool-builder"
    ansible_connection: kubectl
    ansible_kubectl_container: nodepool-builder
    ansible_kubectl_pod: "nodepool-builder-0"

EOF

mkdir -p roles/setup-k8s-config/tasks
cat << EOF > roles/setup-k8s-config/tasks/main.yaml
- name: ensure config dir
  file:
    path: "{{ ansible_env.HOME }}/.kube"
    state: directory

- name: copy secret content
  ansible.builtin.copy:
    content: "{{ k8s_config['ca.crt'] }}"
    dest: "{{ ansible_env.HOME }}/.kube/ca.crt"
    mode: "0600"

- name: setup config
  command: "{{ item }}"
  no_log: true
  loop:
    - "kubectl config set-cluster local --server='{{ k8s_config['server'] }}' --certificate-authority={{ ansible_env.HOME }}/.kube/ca.crt"
    - "kubectl config set-credentials local-token --token={{ k8s_config['token'] }}"
    - "kubectl config set-context local-context --cluster=local --user=local-token --namespace={{ k8s_config['namespace'] }}"
    - "kubectl config use-context local-context"
EOF

git add zuul.d playbooks roles

if [ ! -z "$(git status --porcelain)" ]; then
  git commit -m"Set system config base jobs"
  git push origin master
fi
