# PrestaShop on AWS (Free Tier) — Live Deployment

PrestaShop 8.2.9 on an EC2 application server with MySQL 8.0 on a **separate Amazon RDS host**, inside AWS Free Tier limits.

> **Status:** **Successfully Deployed and Live.**
> 
> * **Storefront URL:** http://ec2-44-213-194-216.compute-1.amazonaws.com/
> * **Database:** Amazon RDS MySQL 8.0 (`prestashop-mysql...rds.amazonaws.com`)
> * **Architecture:** Application and Database are hosted on separate servers (proven in the documentation).

## Project Overview

This repository contains the infrastructure scripts, installation automation, and documentation for deploying PrestaShop 8.2.9 to AWS. 

The environment consists of:
* A custom VPC (`10.20.0.0/16`) with public subnets for the app and private subnets for the database.
* An EC2 `t4g.small` instance running Ubuntu 22.04 and Nginx.
* A separate Amazon RDS `db.t4g.micro` instance running MySQL 8.0 (not co-located with the application).

## Submission Deliverables (as per assignment)

1. **Working Public URL:** [http://ec2-44-213-194-216.compute-1.amazonaws.com/](http://ec2-44-213-194-216.compute-1.amazonaws.com/)
2. **Step-by-Step Documentation:** See [`docs/implementation-runbook.md`](docs/implementation-runbook.md).
3. **AWS Console Screenshots:** The capture guide is [`docs/screenshot-checklist.md`](docs/screenshot-checklist.md), which numbers every exhibit **S1–S16** and states what each frame must show and which requirement it proves. The captured images are submitted alongside the report rather than stored in this repository: `docs/screenshots/` does not exist here, and `.gitignore` excludes `screenshots/*.png` on purpose, because AWS Console frames expose account IDs and credentials.

## Verification Proof

The deployment was verified using the included `verify-deployment.sh` script, which returned a 100% pass rate:

```text
Verifying http://ec2-44-213-194-216.compute-1.amazonaws.com/
--------------------------------------------------------------------
PASS  Storefront responds                                  HTTP 200
PASS  Installer directory is gone                          HTTP 403
PASS  Config directory not exposed                         HTTP 403
PASS  Static theme asset served                            HTTP 200
--------------------------------------------------------------------
Passed: 4   Failed: 0
