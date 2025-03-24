# Development and testing with MicroShift

This document provides instructions on how to deploy a [MicroShift](https://github.com/openshift/microshift) instance on a CentOS 9 Stream host, from your development computer.

We use Microshift as the target **OpenShift instance** for SF-Operator when deploying, developing locally, or testing in our [CI](https://microshift.softwarefactory-project.io/zuul/t/sf/builds?project=software-factory%2Fsf-operator&skip=0).

The deployment will be performed via sf-operator CLI.

1. [Requirements](#requirements)
1. [Install MicroShift](#install-microshift)

## Requirements

### Host

Here are the minimal and recommended specs for your MicroShift host:

| Property | Minimum | Recommended |
|------------|-------------|----------|
| CPUs/vCPUS | 2 | 4 |
| RAM | 8GB | 16GB |
| HDD | 40GB | 100GB |
| OS | RHEL 9.4 | RHEL 9.4 |

You must also be able to reach the following ports on the MicroShift host:

* TCP/6443
* TCP/22 (SSH)

Access your machine via ssh, then ensure that your user have sudo privileges:

```sh
sudo -i
```

Ensure, your system is registered and up to date:

```sh
sudo rhc connect --activation-key <my-key> --organization <my-org-id>
# pin to 9.4
sudo subscription-manager release --set 9.4
sudo dnf update -y
sudo reboot
```

Note that you can register and connect to https://console.redhat.com/insights/connector/activation-keys to
get an activation key for your RHEL machine.

### Pull Secret

MicroShift requires a **pull secret** to access its container registry.

You can generate a pull secret [here](https://cloud.redhat.com/openshift/create/local) and copy in your clipboard.

```sh
export OS_PULL_SECRET="<paste-the-pull-secret-content-here>"
cat << EOF > ~/openshift-pull-secret.yaml
openshift_pull_secret: ${OS_PULL_SECRET}
EOF
```

## Install MicroShift

From your microshift machine:

```shell
cd sf-operator
hack/microshit/setup-microshift.sh localhost

ℹ️  This command logs into /home/fboucher/.cache/setup-microshift.log

▶️  == Running preparation steps ==
⏳ Running ensure_pull_secret ... ✅
⏳ Running ensure_basic_tools ... ✅
⏳ Running ensure_ansible_galaxy_collections ... ✅
⏳ Running ensure_ansible_inventory ... ✅
⏳ Running ensure_microshift_ansible_role ... ✅

▶️  == Deploying MicroShift on cloud-user@microshift.dev (~5 minutes) ==
⏳ Running ensure_microshift ... ✅
⏳ Running ensure_local_kubeconfig ... ✅

🚀 Deploying Microshift done 🚀

To access the deployment, run: KUBECONFIG=~/.kube/microshift-config kubectl -n sf get pods
```

Once the deployment has ended successfully, you are now ready to deploy and hack SF-Operator, congratulations!

Note that the script can be run from a remote machine to with (where <remote-machine> is the RHEL machine):

```sh
hack/microshit/setup-microshift.sh <remote-machine> <remote-user>
```
