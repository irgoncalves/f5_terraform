# Deploying BIG-IP VEs in Google - Auto Scale (Active/Active): 3-NIC

## Contents

- [Introduction](#introduction)
- [Prerequisites](#prerequisites)
- [Important Configuration Notes](#important-configuration-notes)
- [BIG-IQ License Manager](#big-iq-license-manager)
- [Installation Example](#installation-example)
- [Configuration Example](#configuration-example)

## Introduction

This solution uses a Terraform template to launch a 3-NIC deployment of a cloud-focused BIG-IP VE cluster (Active/Active) in Google GCP. It uses [Google Managed Instance Groups (MIG)](https://cloud.google.com/compute/docs/instance-groups) to allow auto scaling and auto healing of the BIG-IP VE devices. Traffic flows from a Google Load Balancer (GLB) to the BIG-IP VE which then processes the traffic to application servers. The BIG-IP VE instance is running with multiple interfaces: management, external, internal. NIC0 is associated with the external network and used in Google MIGs.

The BIG-IP VEs have the [Local Traffic Manager (LTM)](https://f5.com/products/big-ip/local-traffic-manager-ltm) module enabled to provide advanced traffic management functionality. In addition, the [Application Security Module (ASM)](https://www.f5.com/pdf/products/big-ip-application-security-manager-overview.pdf) can be enabled to provide F5's L4/L7 security features for web application firewall (WAF) and bot protection.

Terraform is beneficial as it allows composing resources a bit differently to account for dependencies into Immutable/Mutable elements. For example, mutable includes items you would typically frequently change/mutate, such as traditional configs on the BIG-IP. Once the template is deployed, there are certain resources (network infrastructure) that are fixed while others (BIG-IP VMs and configurations) can be changed.

This template deploys each BIG-IP in an Google MIG as a standalone device and NOT in a [BIG-IP Device Service Cluster (DSC)](https://www.youtube.com/watch?v=NEguvpkmteM). As a result, there is no traditional BIG-IP clustering in regards to config sync and/or network failover. Each device is standalone, each device retrieves its onboarding from custom-data, and each device is treated as [immutable](https://www.f5.com/company/blog/you-cant-do-immutable-infrastructure-without-a-per-app-architecture). If changes are required to the network/application config of the BIG-IP device, then you do this in custom-data via changes to Terraform TF files. The Google MIG will perform a rolling upgrade (aka replacement) of each BIG-IP device.

Example...

-> Run once
- Deploy the entire infrastructure with all the neccessary resources, then use Declarative Onboarding (DO) to configure the BIG-IP cluster, Application Services (AS3) to create a sample app proxy, then lastly use Service Discovery to automatically add the DVWA container app to the BIG-IP pool.

-> Run many X
- [Redeploy BIG-IP for Replacement or Upgrade](#Redeploy-BIG-IP-for-replacement-or-upgrade)

**Networking Stack Type:** This solution deploys into an *EXISTING* networking stack. You are required to have existing VPC networks, firewall rules, and proper routing. Refer to the [Prerequisites](#prerequisites). Visit DevCentral to read [Service Discovery in Google Cloud with F5 BIG-IP](https://devcentral.f5.com/s/articles/Service-Discovery-in-Google-Cloud-with-F5-BIG-IP) where I show you my basic VPC setup (networks, subnets) along with firewall rules.

## Prerequisites

- ***Important***: When you configure the admin password for the BIG-IP VE in the template, you cannot use the character **#**.  Additionally, there are a number of other special characters that you should avoid using for F5 product user accounts.  See [K2873](https://support.f5.com/csp/article/K2873) for details.
- This template requires one or more service accounts for the BIG-IP instance to perform various tasks:
  - See Google's [Understanding service accounts](https://cloud.google.com/iam/docs/understanding-service-accounts)
  - Google Secret Manager secrets access - requires "Secrets Manager Secret Accessor"
    - Performed by VM instance during onboarding to retrieve passwords and private keys
  - Backend pool service discovery - requires "Compute Viewer"
    - Performed by F5 Application Services AS3
  - Google Cloud Monitoring (aka StackDriver) - requires "Monitoring Editor"
    - Performed by F5 Telemetry Streaming
- This template requires a service account to deploy with the Terraform Google provider and build out all the neccessary Google objects
  - See the [Terraform Google Provider "Adding Credentials"](https://www.terraform.io/docs/providers/google/guides/getting_started.html#adding-credentials) for details. Also, review the [available Google GCP permission scopes](https://cloud.google.com/sdk/gcloud/reference/alpha/compute/instances/set-scopes#--scopes) too.
  - Permissions will depend on the objects you are creating
  - My service account for Terraform deployments in GCP uses the following roles:
    - Compute Admin
    - Storage Admin
    - Service Account User
    - Service Account Admin
    - Project IAM Admin
  - ***Note***: Make sure to [practice least privilege](https://cloud.google.com/iam/docs/understanding-service-accounts#granting_minimum)
- ***Shared Service Accounts***: For lab purposes, you can create one service account and use it for everything. Alternatively, you can create a more secure environment with separate service accounts for various functions. Example...
  - Service Account #1 - the svc-acct used for Terraform to deploy cloud objects
  - Service Account #2 - the svc-acct assigned to BIG-IP instance during creation (ex. service discovery, query Pub/Sub, storage)
  - Service Account #3 - the svc-acct used in F5 Telemetry Streaming referenced in [ts.json](./ts.json) (ex. analytics)
- Passwords and secrets are located in [Google Cloud Secret Manager](https://cloud.google.com/secret-manager/docs/quickstart#secretmanager-quickstart-web). Make sure you have an existing Google Cloud "secret" with the data containing the clear text passwords for each relevant item: BIG-IP password, service account credentials, BIG-IQ password, etc.
  - 'usecret' contains the value of the adminstrator password (ex. "Default12345!")
  - 'ksecret' Contains the value of the 'svc_acct' private key. Currently used for BIG-IP telemetry streaming to Google Cloud Monitoring (aka StackDriver). If you are not using this feature, you do not need this secret in Secret Manager.
  - Refer to [Template Parameters](#template-parameters)
- This template deploys into an existing network
  - You must have a VPC for management and a VPC for data traffic (client/server). The management VPC will have one subnet for management traffic. The External VPC will have one subnet for data traffic. The Internal VPC will have one subnet as well.
  - Firewall rules are required to pass traffic to the application
    - BIG-IP will require tcp/22 and tcp/443 on the mgmt network
    - Application access will require tcp/80 and tcp/443 on the external network
    - Google Health Checks will require tcp/40000 on the external network. Refer to [Google Health Check Concepts](https://cloud.google.com/load-balancing/docs/health-check-concepts) to see source IP ranges for the Google probes. These IP ranges and ports (tcp/40000 in this example) need to be open in your firewall rules on the external network.
  - If you require a new network first, see the [Infrastructure Only folder](../Infrastructure-only) to get started.
  - The parameter 'dns_suffix' must match the DNS suffix assigned by the GCP project. You can retrieve this value by logging into an existing VM in the same project and running 'uname -a' or reviewing the /etc/resolv.conf file. Failure to properly set 'dns_suffix' will result in failed hostname lookup during HA setup.


## Important Configuration Notes

- Variables are configured in variables.tf
- Sensitive variables like Google SSH keys are configured in terraform.tfvars
  - ***Note***: Other items like BIG-IP password are stored in Google Cloud Secret Manager. Refer to the [Prerequisites](#prerequisites).
  - The BIG-IP instance will query Google Metadata API to retrieve the service account's token for authentication.
  - The BIG-IP instance will then use the secret name and the service account's token to query Google Metadata API and dynamically retrieve the password for device onboarding.
- This template uses Declarative Onboarding (DO) and Application Services 3 (AS3) for the initial configuration. As part of the onboarding script, it will download the RPMs automatically. See the [AS3 documentation](http://f5.com/AS3Docs) and [DO documentation](http://f5.com/DODocs) for details on how to use AS3 and Declarative Onboarding on your BIG-IP VE(s). The [Telemetry Streaming](http://f5.com/TSDocs) extension is also downloaded and can be configured to point to [F5 Beacon](https://f5.com/beacon-get-started), Google Cloud Monitoring (old name StackDriver), or many other consumers.
- Files
  - bigip.tf - resources for BIG-IP, NICs, public IPs
  - glb.tf - resources for Google LB
  - main.tf - resources for provider, versions
  - onboard.tpl - onboarding script which is run by startup-script (user data). It will be copied to **startup-script=*path-to-file*** upon bootup. This script is responsible for downloading the neccessary F5 Automation Toolchain RPM files, installing them, and then executing the onboarding REST calls.
  - do.json - contains the L1-L3 BIG-IP configurations used by DO for items like VLANs, IPs, and routes
  - as3.json - contains the L4-L7 BIG-IP configurations used by AS3 for items like pool members, virtual server listeners, security policies, and more
  - ts.json - contains the BIG-IP configurations used by TS for items like telemetry streaming, CPU, memory, application statistics, and more

## BIG-IQ License Manager
This template uses PayGo BIG-IP image for the deployment (as default). If you would like to use BYOL/ELA/Subscription licenses from [BIG-IQ License Manager (LM)](https://devcentral.f5.com/s/articles/managing-big-ip-licensing-with-big-iq-31944), then these following steps are needed:
1. Find available images/versions with "byol" in the name using Google gcloud:
  ```
          gcloud compute images list --project=f5-7626-networks-public | grep f5

          # example output...

          --snippet--
          f5-bigip-13-1-3-2-0-0-4-payg-best-1gbps-20191105210022
          f5-bigip-13-1-3-2-0-0-4-payg-best-200mbps-20191105210022
          f5-bigip-13-1-3-2-0-0-4-byol-all-modules-2slot-20191105200157
          ...and some more
          f5-bigip-14-1-2-3-0-0-5-byol-ltm-1boot-loc-191218142225
          f5-bigip-15-1-2-1-0-0-10-payg-best-1gbps-210115161130
          f5-bigip-15-1-2-1-0-0-10-byol-ltm-2boot-loc-210115160742
          ...and more...
  ```
2. In the "variables.tf", modify *image_name* with the image name from gcloud CLI results
  ```
          # BIGIP Image
          variable image_name { default = "projects/f5-7626-networks-public/global/images/f5-bigip-15-1-2-1-0-0-10-byol-ltm-2boot-loc-210115160742" }
  ```
3. In the "variables.tf", modify the BIG-IQ license section to match your environment
4. In the "do.json", add the "myLicense" block under the "Common" declaration ([full declaration example here](https://clouddocs.f5.com/products/extensions/f5-declarative-onboarding/latest/bigiq-examples.html#licensing-with-big-iq-regkey-pool-route-to-big-ip))
  ```
        "myLicense": {
            "class": "License",
            "licenseType": "${bigIqLicenseType}",
            "bigIqHost": "${bigIqHost}",
            "bigIqUsername": "${bigIqUsername}",
            "bigIqPassword": "$${bigIqPassword}",
            "licensePool": "${bigIqLicensePool}",
            "skuKeyword1": "${bigIqSkuKeyword1}",
            "skuKeyword2": "${bigIqSkuKeyword2}",
            "unitOfMeasure": "${bigIqUnitOfMeasure}",
            "reachable": false,
            "hypervisor": "${bigIqHypervisor}",
            "overwrite": true
        },
  ```
  ***Note***: The [onboard.tpl](./onboard.tpl) startup script will use the same 'usecret' payload value (aka password) for BIG-IP password AND the BIG-IQ password. In the onboard.tpl file, this happens in the 'passwd' variable. You can use a separate password for BIG-IQ by creating a new Google Secret Manager secret for the BIG-IQ password, then add a new variable for the secret in [variables.tf](./variables.tf), modify [bigip.tf](./bigip.tf) to include the secret in the local templatefile section similar to 'usecret', then update [onboard.tpl](./onboard.tpl) to query Secret Manager for the BIG-IQ secret name. Reference code example *usecret='${usecret}'*.

<!-- markdownlint-disable no-inline-html -->
<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 0.14 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 3 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | ~> 3 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [google_compute_address.vip1](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_address) | resource |
| [google_compute_forwarding_rule.vip1](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_forwarding_rule) | resource |
| [google_compute_health_check.f5vm](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_health_check) | resource |
| [google_compute_http_health_check.hc-ext](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_http_health_check) | resource |
| [google_compute_instance_template.f5vm](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_instance_template) | resource |
| [google_compute_region_autoscaler.f5vm](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_region_autoscaler) | resource |
| [google_compute_region_instance_group_manager.f5vm](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_region_instance_group_manager) | resource |
| [google_compute_target_pool.f5vm](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_target_pool) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_AS3_URL"></a> [AS3\_URL](#input\_AS3\_URL) | URL to download the BIG-IP Application Service Extension 3 (AS3) module | `string` | `"https://github.com/F5Networks/f5-appsvcs-extension/releases/download/v3.30.0/f5-appsvcs-3.30.0-5.noarch.rpm"` | no |
| <a name="input_DO_URL"></a> [DO\_URL](#input\_DO\_URL) | URL to download the BIG-IP Declarative Onboarding module | `string` | `"https://github.com/F5Networks/f5-declarative-onboarding/releases/download/v1.23.0/f5-declarative-onboarding-1.23.0-4.noarch.rpm"` | no |
| <a name="input_TS_URL"></a> [TS\_URL](#input\_TS\_URL) | URL to download the BIG-IP Telemetry Streaming module | `string` | `"https://github.com/F5Networks/f5-telemetry-streaming/releases/download/v1.22.0/f5-telemetry-1.22.0-1.noarch.rpm"` | no |
| <a name="input_adminSrcAddr"></a> [adminSrcAddr](#input\_adminSrcAddr) | Trusted source network for admin access | `string` | `"0.0.0.0/0"` | no |
| <a name="input_auto_healing_initial_delay_sec"></a> [auto\_healing\_initial\_delay\_sec](#input\_auto\_healing\_initial\_delay\_sec) | The number of seconds that the managed instance group waits before it applies autohealing policies to new instances or recently recreated instances | `number` | `900` | no |
| <a name="input_autoscaling_cooldown_period"></a> [autoscaling\_cooldown\_period](#input\_autoscaling\_cooldown\_period) | The number of seconds that the autoscaler should wait before it starts collecting information from a new instance | `number` | `900` | no |
| <a name="input_autoscaling_cpu_target"></a> [autoscaling\_cpu\_target](#input\_autoscaling\_cpu\_target) | The target CPU utilization that the autoscaler should maintain | `string` | `".7"` | no |
| <a name="input_autoscaling_max_replicas"></a> [autoscaling\_max\_replicas](#input\_autoscaling\_max\_replicas) | The maximum number of instances that the autoscaler can scale up to | `number` | `4` | no |
| <a name="input_autoscaling_min_replicas"></a> [autoscaling\_min\_replicas](#input\_autoscaling\_min\_replicas) | The minimum number of replicas that the autoscaler can scale down to | `number` | `2` | no |
| <a name="input_bigIqHost"></a> [bigIqHost](#input\_bigIqHost) | This is the BIG-IQ License Manager host name or IP address | `string` | `""` | no |
| <a name="input_bigIqHypervisor"></a> [bigIqHypervisor](#input\_bigIqHypervisor) | BIG-IQ hypervisor | `string` | `"gce"` | no |
| <a name="input_bigIqLicensePool"></a> [bigIqLicensePool](#input\_bigIqLicensePool) | BIG-IQ license pool name | `string` | `""` | no |
| <a name="input_bigIqLicenseType"></a> [bigIqLicenseType](#input\_bigIqLicenseType) | BIG-IQ license type | `string` | `"licensePool"` | no |
| <a name="input_bigIqSkuKeyword1"></a> [bigIqSkuKeyword1](#input\_bigIqSkuKeyword1) | BIG-IQ license SKU keyword 1 | `string` | `"key1"` | no |
| <a name="input_bigIqSkuKeyword2"></a> [bigIqSkuKeyword2](#input\_bigIqSkuKeyword2) | BIG-IQ license SKU keyword 2 | `string` | `"key2"` | no |
| <a name="input_bigIqUnitOfMeasure"></a> [bigIqUnitOfMeasure](#input\_bigIqUnitOfMeasure) | BIG-IQ license unit of measure | `string` | `"hourly"` | no |
| <a name="input_bigIqUsername"></a> [bigIqUsername](#input\_bigIqUsername) | Admin name for BIG-IQ | `string` | `"admin"` | no |
| <a name="input_bigipMachineType"></a> [bigipMachineType](#input\_bigipMachineType) | Google machine type to be used for the BIG-IP VE | `string` | `"n1-standard-8"` | no |
| <a name="input_customImage"></a> [customImage](#input\_customImage) | A custom SKU (image) to deploy that you provide. This is useful if you created your own BIG-IP image with the F5 image creator tool. | `string` | `""` | no |
| <a name="input_customUserData"></a> [customUserData](#input\_customUserData) | The custom user data to deploy when using the 'customImage' paramater too. | `string` | `""` | no |
| <a name="input_dns_server"></a> [dns\_server](#input\_dns\_server) | Leave the default DNS server the BIG-IP uses, or replace the default DNS server with the one you want to use | `string` | `"8.8.8.8"` | no |
| <a name="input_dns_suffix"></a> [dns\_suffix](#input\_dns\_suffix) | DNS suffix for your domain in the GCP project | `string` | `"example.com"` | no |
| <a name="input_extSubnet"></a> [extSubnet](#input\_extSubnet) | External subnet | `string` | `null` | no |
| <a name="input_extVpc"></a> [extVpc](#input\_extVpc) | External VPC network | `string` | `null` | no |
| <a name="input_gceSshPubKey"></a> [gceSshPubKey](#input\_gceSshPubKey) | SSH public key for admin authentation | `string` | `null` | no |
| <a name="input_gcp_project_id"></a> [gcp\_project\_id](#input\_gcp\_project\_id) | GCP Project ID for provider | `string` | `null` | no |
| <a name="input_gcp_region"></a> [gcp\_region](#input\_gcp\_region) | GCP Region for provider | `string` | `"us-west1"` | no |
| <a name="input_gcp_zone"></a> [gcp\_zone](#input\_gcp\_zone) | GCP Zone for provider | `string` | `"us-west1-b"` | no |
| <a name="input_image_name"></a> [image\_name](#input\_image\_name) | F5 SKU (image) to deploy. Note: The disk size of the VM will be determined based on the option you select.  **Important**: If intending to provision multiple modules, ensure the appropriate value is selected, such as ****AllTwoBootLocations or AllOneBootLocation****. | `string` | `"projects/f5-7626-networks-public/global/images/f5-bigip-15-1-2-1-0-0-10-payg-best-1gbps-210115161130"` | no |
| <a name="input_intSubnet"></a> [intSubnet](#input\_intSubnet) | Internal subnet | `string` | `null` | no |
| <a name="input_intVpc"></a> [intVpc](#input\_intVpc) | Internal VPC network | `string` | `null` | no |
| <a name="input_ksecret"></a> [ksecret](#input\_ksecret) | Contains the value of the 'svc\_acct' private key. Currently used for BIG-IP telemetry streaming to Google Cloud Monitoring (aka StackDriver). If you are not using this feature, you do not need this secret in Secret Manager. | `string` | `""` | no |
| <a name="input_mgmtSubnet"></a> [mgmtSubnet](#input\_mgmtSubnet) | Management subnet | `string` | `null` | no |
| <a name="input_mgmtVpc"></a> [mgmtVpc](#input\_mgmtVpc) | Management VPC network | `string` | `null` | no |
| <a name="input_ntp_server"></a> [ntp\_server](#input\_ntp\_server) | Leave the default NTP server the BIG-IP uses, or replace the default NTP server with the one you want to use | `string` | `"0.us.pool.ntp.org"` | no |
| <a name="input_onboard_log"></a> [onboard\_log](#input\_onboard\_log) | This is where the onboarding script logs all the events | `string` | `"/var/log/cloud/onboard.log"` | no |
| <a name="input_owner"></a> [owner](#input\_owner) | This is a tag used for object creation. Example is last name. | `string` | `null` | no |
| <a name="input_prefix"></a> [prefix](#input\_prefix) | This value is inserted at the beginning of each Google object (alpha-numeric, no special character) | `string` | `"demo"` | no |
| <a name="input_privateKeyId"></a> [privateKeyId](#input\_privateKeyId) | ID of private key for the 'svc\_acct' used in Telemetry Streaming to Google Cloud Monitoring. If you are not using this feature, you do not need this secret in Secret Manager. | `string` | `""` | no |
| <a name="input_svc_acct"></a> [svc\_acct](#input\_svc\_acct) | Service Account for VM instance | `string` | `null` | no |
| <a name="input_timezone"></a> [timezone](#input\_timezone) | If you would like to change the time zone the BIG-IP uses, enter the time zone you want to use. This is based on the tz database found in /usr/share/zoneinfo (see the full list [here](https://cloud.google.com/dataprep/docs/html/Supported-Time-Zone-Values_66194188)). Example values: UTC, US/Pacific, US/Eastern, Europe/London or Asia/Singapore. | `string` | `"UTC"` | no |
| <a name="input_uname"></a> [uname](#input\_uname) | User name for the Virtual Machine | `string` | `"admin"` | no |
| <a name="input_update_policy_max_surge_fixed"></a> [update\_policy\_max\_surge\_fixed](#input\_update\_policy\_max\_surge\_fixed) | The maximum number of instances that can be created above the specified targetSize during the update process | `number` | `3` | no |
| <a name="input_update_policy_max_unavailable_fixed"></a> [update\_policy\_max\_unavailable\_fixed](#input\_update\_policy\_max\_unavailable\_fixed) | The maximum number of instances that can be unavailable during the update process | `number` | `0` | no |
| <a name="input_update_policy_min_ready_sec"></a> [update\_policy\_min\_ready\_sec](#input\_update\_policy\_min\_ready\_sec) | Minimum number of seconds to wait for after a newly created instance becomes available | `number` | `0` | no |
| <a name="input_update_policy_minimal_action"></a> [update\_policy\_minimal\_action](#input\_update\_policy\_minimal\_action) | Minimal action to be taken on an autoscale instance | `string` | `"REPLACE"` | no |
| <a name="input_update_policy_type"></a> [update\_policy\_type](#input\_update\_policy\_type) | The type of autoscale update process | `string` | `"PROACTIVE"` | no |
| <a name="input_usecret"></a> [usecret](#input\_usecret) | Used during onboarding to query the Google Cloud Secret Manager API and retrieve the admin password (use the secret name, not the secret value/password) | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_public_vip"></a> [public\_vip](#output\_public\_vip) | public IP address for application |
| <a name="output_public_vip_url"></a> [public\_vip\_url](#output\_public\_vip\_url) | public URL for application |
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
<!-- markdownlint-enable no-inline-html -->

## Installation Example

To run this Terraform template, perform the following steps:
  1. Clone the repo to your favorite location
  2. Modify terraform.tfvars with the required information
  ```
      # BIG-IP Environment
      uname        = "admin"
      usecret      = "my-secret"
      gceSshPubKey = "ssh-rsa xxxxx
      prefix       = "mydemo123"
      adminSrcAddr = "0.0.0.0/0"
      mgmtVpc      = "xxxxx-net-mgmt"
      extVpc       = "xxxxx-net-ext"
      intVpc       = "xxxxx-net-int"
      mgmtSubnet   = "xxxxx-subnet-mgmt"
      extSubnet    = "xxxxx-subnet-ext"
      intSubnet    = "xxxxx-subnet-int"
      dns_suffix   = "c.xxxxx.xxxxx.internal"

      # BIG-IQ Environment
      bigIqUsername = "admin"

      # Google Environment
      gcp_project_id = "xxxxx"
      gcp_region     = "us-west1"
      gcp_zone       = "us-west1-b"
      svc_acct       = "xxxxx@xxxxx.iam.gserviceaccount.com"
  ```
  3. Initialize the directory
  ```
      terraform init
  ```
  4. Test the plan and validate errors
  ```
      terraform plan
  ```
  5. Finally, apply and deploy
  ```
      terraform apply
  ```
  6. When done with everything, don't forget to clean up!
  ```
      terraform destroy
  ```

## Configuration Example

The following is an example configuration diagram for this solution deployment. In this scenario, all access to the BIG-IP VE cluster (Active/Active) is direct to each BIG-IP via the management interface. The IP addresses in this example may be different in your implementation.

![Configuration Example](./images/gcp-bigip-autoscale-via-lb.png)

## Documentation

For more information on F5 solutions for Google, including manual configuration procedures for some deployment scenarios, see the Google GCP section of [F5 CloudDocs](https://clouddocs.f5.com/cloud/public/v1/google_index.html). Also check out the [Using Cloud Templates for BIG-IP in Google](https://devcentral.f5.com/s/articles/Using-Cloud-Templates-to-Change-BIG-IP-Versions-Google) on DevCentral. This particular auto scale example is based on the [BIG-IP Auto Scale F5 GDM Cloud Template on GitHub](https://github.com/F5Networks/f5-google-gdm-templates/tree/master/experimental/autoscale/waf/via-lb/existing-stack/payg).

## Creating Virtual Servers on the BIG-IP VE

In order to pass traffic from your clients to the servers through the BIG-IP system, you must create a virtual server on the BIG-IP VE. In this template, the AS3 declaration creates 1 VIP listening on 0.0.0.0/0, port 443. It is preconfigured as an example.

In this template, the Google public IP address is associated with the Google External Load Balancer (GLB) which has a target-pool containing both BIG-IP devices as backends. The address is created with a [Google Forwarding Rule](https://cloud.google.com/load-balancing/docs/forwarding-rule-concepts).

***Note:*** These next steps illustrate the manual way in the GUI to create a virtual server
1. Open the BIG-IP VE Configuration utility
2. Click **Local Traffic > Virtual Servers**
3. Click the **Create** button
4. Type a name in the **Name** field
4. Type an address (ex. 0.0.0.0/0) in the **Destination/Mask** field
5. Type a port (ex. 443) in the **Service Port**
6. Configure the rest of the virtual server as appropriate
7. Select a pool name from the **Default Pool** list
8. Click the **Finished** button
9. Repeat as necessary for other applications by using different ports (ex. 0.0.0.0/0:9443, 0.0.0.0/0:8444)

## Redeploy BIG-IP for Replacement or Upgrade
This example illustrates how to replace or upgrade the BIG-IP VE.
  1. Change the *image_name* variable to the desired release
  2. Revoke the problematic BIG-IP VE's license (if BYOL)
  3. Run command
```
terraform taint google_compute_instance.f5vm01
```
  3. Run command
```
terraform apply
```
