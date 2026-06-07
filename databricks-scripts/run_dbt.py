# Databricks notebook source
# Helper script to run dbt commands from Databricks workflows

import sys
import subprocess
import json
from datetime import datetime

# Get parameters
dbutils.widgets.text("dbt_command", "", "dbt command to run")
dbt_command = dbutils.widgets.get("dbt_command")

print(f"Running dbt command: {dbt_command}")
print(f"Start time: {datetime.now()}")

# Change to dbt project directory
dbt_project_dir = "/dbfs/dbt/customer_360"

try:
    # Run dbt command
    result = subprocess.run(
        f"cd {dbt_project_dir} && dbt {dbt_command}",
        shell=True,
        capture_output=True,
        text=True,
        timeout=3600
    )

    print(result.stdout)

    if result.returncode != 0:
        print(f"ERROR: {result.stderr}")
        raise Exception(f"dbt command failed with exit code {result.returncode}")

    print(f"End time: {datetime.now()}")
    print("SUCCESS")

except subprocess.TimeoutExpired:
    raise Exception("dbt command timed out after 1 hour")
except Exception as e:
    raise Exception(f"Failed to run dbt command: {str(e)}")
