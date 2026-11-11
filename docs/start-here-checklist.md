# Start here — the simple checklist

A beginner's version of the deployment. Six steps, in order. Do not skip ahead.

If you want the full technical detail, it is in
[implementation-runbook.md](implementation-runbook.md). You do not need it to finish.

---

## What you are building

Two separate computers inside AWS:

* **Computer 1** — the web server. Runs PrestaShop, the shop software people visit.
* **Computer 2** — the database. Stores the products, customers and orders.

The assignment says the database must **not** be on the same machine as the
application. That is exactly what this builds. You do not have to create either
machine by hand: one command creates both, correctly.

---

## Step 1 — Sign in and set the region

- [ ] Go to `console.aws.amazon.com` and sign in.
- [ ] Look at the **top-right corner**. It shows a region, e.g. *N. Virginia*.
- [ ] If it shows anything other than **US East (N. Virginia)**, click it and pick that.
      Everything in this project assumes `us-east-1`.

## Step 2 — Put a $1 alarm on the account

- [ ] In the search bar at the top, type `Budgets` and open it.
- [ ] **Create budget** → *Monthly cost budget* → amount `1` → your email → **Create**.

This is a smoke alarm. If AWS ever starts charging real money, you get an email
instead of a surprise next month. The whole stack is designed to sit inside the
free tier, but the alarm is the safety net.

## Step 3 — Open CloudShell

- [ ] In the search bar type `CloudShell` and open it.
- [ ] A terminal appears at the bottom of the page. It is already signed in as you.
      You never type an access key or a password. That is the point of this route.
- [ ] Check the region shown in CloudShell is also **us-east-1**.

## Step 4 — Get the files and tell the script your IP

Paste these lines into CloudShell, one line at a time, pressing **Enter** after each.

```
git clone https://github.com/Azeru548/bincomdev-submision
```

```
cd bincomdev-submision
```

- [ ] Now find your IP address: open a **new browser tab**, go to the checkip
      service page (`https://checkip.amazonaws.com`), and copy the number it shows —
      four groups like `102.89.34.12`.
- [ ] Back in CloudShell, put your number in place of the example and press Enter:

```
export ADMIN_CIDR="102.89.34.12/32"
```

Keep the `/32` at the end. This tells AWS to accept SSH connections from you and
nobody else. Nothing visible happens — that is correct.

## Step 5 — Start the build and wait

- [ ] Paste this and press Enter:

```
bash scripts/deploy-aws-cli.sh
```

- [ ] It prints progress lines like `==> creating VPC`, `==> waiting for RDS`.
- [ ] **Wait about 20 minutes.** Do not close the tab. Do not press Ctrl-C.
- [ ] The database is created first and takes the longest; the web server then
      installs PrestaShop on its own.
- [ ] At the end it prints a URL starting with `http://ec2-...`. Copy that URL.

If CloudShell disconnects or times out, reconnect and run `bash scripts/deploy-aws-cli.sh`
again. It is written to reuse what already exists instead of creating duplicates.

## Step 6 — Open the shop

- [ ] Paste the printed URL into a new browser tab.
- [ ] You should see the PrestaShop shop front page.

If you see a shop instead of an error page, the hard part is done.

---

## After it works — send me this

Tell me **"it worked"** and paste the URL. I will then give you the short list of
AWS Console pages to screenshot for your submission, in the order your report needs
them.

## If something goes wrong

Copy the **last 20 lines** of the terminal output and send them to me. The three
most common situations:

| What you see | What it means |
|---|---|
| `ADMIN_CIDR` error at the start | Step 4 did not run, or the `/32` is missing. Re-run the `export` line. |
| `cannot reach ...:3306` in the log | The database is still starting, or the firewall rule is not in place. |
| A 502 or blank page in the browser | The web server is still finishing its install. Wait 5 minutes and reload. |

## Important

**Do not delete the instance, the database or the VPC until your work has been
graded.** When you are finished, I will give you the single command that removes
everything and stops any billing.
