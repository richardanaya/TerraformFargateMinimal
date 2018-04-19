# A Minimal Fargate Terraform Setup

This project contains the absolute bare minimal for creating a single service, single task Hello World web server using Terraform.

```bash
terraform init
terraform apply -auto-approve
# look up the ip of your task and go to http://<ip4 address>
terraform destroy -auto-approve
```
