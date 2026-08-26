+++++++++++++++++ Doing configuration new way +++++++++++++++++++++++++

Follow the document mentioned found on the link mentioned below:
https://docs.tigera.io/calico/latest/getting-started/kubernetes/self-managed-onprem/onpremises#install-calico

+++++++++++++++++ Doing configuration old way +++++++++++++++++++++++++

You can go and find latest version of Calico, dowload it and chnage pod CIDR from 192.168.0.0/16 to you cluster's pod cidr and apply it.
Calico can be download from https://raw.githubusercontent.com/projectcalico/calico/v3.30.2/manifests/calico.yaml 

Just Change 3.30.2 with latest version.
