# Kubernetes Setup (K3s)

The cluster is provisioned automatically by the lab's Vagrant/provisioning
scripts — you do not need to run `kubeadm` manually. This page documents
what gets installed and how to access it after `vagrant up`.

## Cluster layout

- `devops-1` — K3s control plane, plus Harbor, Argo CD, Prometheus,
  Grafana, Falco, and Kyverno.
- `worker-1`, `worker-2` — K3s agents.

See [`architecture.md`](architecture.md) for the full topology diagram
and current K3s version pin.

## Configure kubectl

From the control-plane node:

```bash
vagrant ssh devops-1
mkdir -p $HOME/.kube
sudo cp /etc/rancher/k3s/k3s.yaml $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
kubectl get nodes
```

K3s ships its own CNI (Flannel) and a bundled `kubectl`/`crictl` —
no separate CNI manifest or `kubeadm join` step is required.

## Worker nodes

`worker-1` and `worker-2` join the cluster automatically during
provisioning once the control plane's cluster state is available; see
[`architecture.md`](architecture.md#deployment-sequence) for the
provisioning sequence.

> Superseded note: earlier revisions of this lab used a manual
> `kubeadm init` / `kubeadm join` workflow with a Calico CNI on nodes
> named `k8s-cp`/`k8s-w1`/`k8s-w2`. That workflow is no longer part of
> this lab — the current provisioning is K3s-based, as described above.
