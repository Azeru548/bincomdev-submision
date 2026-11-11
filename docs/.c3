| Requirement | How it is met | Evidence to submit |
|---|---|---|
| Database not on the application server | Amazon RDS MySQL 8.0 in a private subnet; app connects to a remote endpoint | RDS console screenshot + `ss -ltnp \| grep 3306` returning nothing on EC2 |
| EC2 | 750 h/month of `t2.micro` / `t3.micro` for 12 months | $100 credit + up to $100 more for setup activities |
