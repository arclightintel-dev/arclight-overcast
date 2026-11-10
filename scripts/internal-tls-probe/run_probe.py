"""Run the internal-TLS acceptance probe once (spec docs/proposals/internal-tls-nlb.md, P1).

Operator tool. It needs AWS credentials that may register and run ECS tasks.

    python scripts/internal-tls-probe/run_probe.py --sg <security-group-id> [--name ...]

Steps:
1. Pins Core's live image digest from the running Core task (LIVE_DIGEST).
2. Registers a one-off arclight-probe-<env> revision with no secrets and no task role.
3. Runs it in the given security group, in the subnets of Core's service, with no public IP.
4. Prints the PROBE line and the task's exit, then deregisters the revision.

Run it once with ShuttleForge's group and once with Nerfherder's.
"""
import argparse
import json
import os
import pathlib
import string
import subprocess
import sys
import tempfile
import time

AWS = os.environ.get("AWS_CLI", "C:/Program Files/Amazon/AWSCLIV2/aws.exe")
HERE = pathlib.Path(__file__).resolve().parent


def aws(*args):
    out = subprocess.run([AWS, *args, "--output", "json"], check=True, capture_output=True, text=True)
    return json.loads(out.stdout) if out.stdout.strip() else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sg", required=True, help="security group to run in (SF's or NF's)")
    ap.add_argument("--env", default="staging")
    ap.add_argument("--region", default="us-east-1")
    ap.add_argument("--name", default="core-internal.staging.arclight-complex.net")
    ap.add_argument("--nlb", default="arclight-stg-int-core")
    a = ap.parse_args()
    r = ["--region", a.region]
    cluster = f"arclight-{a.env}"
    svc = aws("ecs", "describe-services", "--cluster", cluster, "--services", f"arclight-core-{a.env}", *r)["services"][0]
    subnets = svc["networkConfiguration"]["awsvpcConfiguration"]["subnets"]
    live_td = svc["taskDefinition"]
    task_arn = aws("ecs", "list-tasks", "--cluster", cluster, "--service-name", f"arclight-core-{a.env}",
                   "--desired-status", "RUNNING", *r)["taskArns"][0]
    task = aws("ecs", "describe-tasks", "--cluster", cluster, "--tasks", task_arn, *r)["tasks"][0]
    live_digest = task["containers"][0]["imageDigest"]
    repo = aws("ecs", "describe-task-definition", "--task-definition", live_td, *r)[
        "taskDefinition"]["containerDefinitions"][0]["image"].split("@")[0].split(":")[0]
    image = f"{repo}@{live_digest}"
    enis = aws("ec2", "describe-network-interfaces", "--filters",
               f"Name=description,Values=ELB net/{a.nlb}/*", *r)["NetworkInterfaces"]
    nodes = sorted(e["PrivateIpAddress"] for e in enis)
    role = aws("iam", "get-role", "--role-name", f"arclight-ecs-exec-probe-{a.env}")["Role"]["Arn"]
    tpl = string.Template((HERE / "task-definition.json.tpl").read_text(encoding="utf-8"))
    td = tpl.substitute(ENVIRONMENT=a.env, EXEC_ROLE_ARN=role, IMAGE=image, REGION=a.region)
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8") as f:
        f.write(td)
        td_path = f.name
    reg = aws("ecs", "register-task-definition", "--cli-input-json",
              "file://" + td_path.replace("\\", "/"), *r)
    probe_td = reg["taskDefinition"]["taskDefinitionArn"]
    print(f"LIVE_TD={live_td}\nLIVE_DIGEST={live_digest}\nPROBE_TD={probe_td}\nNLB_NODES={nodes}\nSG={a.sg}", flush=True)
    code = (HERE / "probe.py").read_text(encoding="utf-8")
    overrides = {"containerOverrides": [{"name": "probe", "command": ["python", "-c", code, a.name, ",".join(nodes)]}]}
    try:
        run = aws("ecs", "run-task", "--cluster", cluster, "--task-definition", probe_td, "--launch-type", "FARGATE",
                  "--network-configuration", json.dumps({"awsvpcConfiguration": {
                      "subnets": subnets, "securityGroups": [a.sg], "assignPublicIp": "DISABLED"}}),
                  "--overrides", json.dumps(overrides), *r)
        tid = run["tasks"][0]["taskArn"]
        print(f"PROBE_TASK={tid}", flush=True)
        subprocess.run([AWS, "ecs", "wait", "tasks-stopped", "--cluster", cluster, "--tasks", tid, *r], check=True)
        t = aws("ecs", "describe-tasks", "--cluster", cluster, "--tasks", tid, *r)["tasks"][0]
        print(f"EXIT={t['containers'][0].get('exitCode')} STOP={t.get('stoppedReason')}", flush=True)
        time.sleep(5)
        ev = aws("logs", "get-log-events", "--log-group-name", f"/arclight/{a.env}/probe",
                 "--log-stream-name", f"probe/probe/{tid.rsplit('/', 1)[1]}", "--start-from-head", *r)
        for e in ev["events"]:
            print(e["message"], flush=True)
    finally:
        aws("ecs", "deregister-task-definition", "--task-definition", probe_td, *r)
        print(f"DEREGISTERED={probe_td}", flush=True)


if __name__ == "__main__":
    sys.exit(main())
