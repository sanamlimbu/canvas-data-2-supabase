# canvas-data-2-supabase

Synchronise Canvas database to Supabase using Canvas Data 2, Instructure DAP library, and AWS.

## Step 1. Initialise database in Supabase

Before executing synchronisation AWS Lambda handler, Supabase must be intialised. The initialisation step will create schemas and populate rows for selected tables.

### 1.1 Setup environment variables

```
DAP_API_URL=""
DAP_CLIENT_ID=""
DAP_CLIENT_SECRET=""
DAP_CONNECTION_STRING="" -- Supabase connection string
TABLES="" -- comma seperated list of tables
```

### 1.1 Execute int_db

After setting up environment variables and installing required dependencies in `requirements.txt`, initialise target database (Supabase) by executing `main.py` file present in `init_db` directory.

## Step 2. Deploy AWS Lambda

AWS Lambda handler present in `sync_db_lambda` is deployed using Terraform. The workflow has remote execution, so setup your HCF Terraform account as required. Also, setup your AWS credentials in Terraform.

### 2.1 Package distribution

`create_package.sh` bash script inside terraform directory, creates a package that will be be deployed as AWS Lambda hanlder. Run the script before deployment.

### 2.2 Environment variables

Following envs are used by the handler. Except `SNS_TOPIC_ARN`, pass other envs as Terraform variables.

```
DAP_API_URL=""
DAP_CLIENT_ID=""
DAP_CLIENT_SECRET=""
DAP_CONNECTION_STRING="" -- Supabase connection string
TABLES="" -- comma seperated list of tables
SNS_TOPIC_ARN="" -- obtained from Terraform
```

### 2.3 Deployment

After setting up AWS credentials, HCF Terraform, and creating package, now, you are ready for deployment.
Here, Terraform CLI is used for deployment.
