import asyncio
import os
from enum import StrEnum

import boto3
from aws_lambda_powertools import Logger
from aws_lambda_powertools.utilities.typing import LambdaContext
from dap.api import DAPClient
from dap.dap_types import Credentials
from dap.integration.database import DatabaseConnection
from dap.integration.database_errors import NonExistingTableError
from dap.replicator.sql import SQLReplicator


class SyncTableResult(StrEnum):
    INIT_NEEDED = "init_needed"
    COMPLETED = "completed"
    FAILED = "failed"
    NO_TABLE = "no_table"


base_url = os.environ.get("DAP_API_URL")
dap_client_id = os.environ.get("DAP_CLIENT_ID")
dap_client_secret = os.environ.get("DAP_CLIENT_SECRET")
db_connection_string = os.environ.get("DAP_CONNECTION_STRING")
tables = os.environ.get("TABLES").split(",")
sns_topic_arn = os.environ.get("SNS_TOPIC_ARN")

namespace = "canvas"

logger = Logger()

client = boto3.client("sns")


def lambda_handler(event, context: LambdaContext):
    credentials = Credentials.create(
        client_id=dap_client_id, client_secret=dap_client_secret
    )

    os.chdir("/tmp/")

    loop = asyncio.get_event_loop()

    results = loop.run_until_complete(main(credentials=credentials))

    log_stream_name = context.log_stream_name

    message = f"Results: {results}\n\nLog Stream: {log_stream_name}"

    response = client.publish(
        TopicArn=sns_topic_arn,
        Message=message,
        Subject="Canvas Data 2 Sync Results",
    )

    logger.info(f"published results to SNS: {response}")

    return event


async def main(credentials: Credentials):
    tasks = [
        sync_table(
            table_name=table_name,
            credentials=credentials,
        )
        for table_name in tables
    ]

    results = await asyncio.gather(*tasks)

    return results


async def sync_table(table_name: str, credentials: Credentials):
    logger.info(f"sync table: {table_name} started...")

    result = SyncTableResult.COMPLETED

    connection = DatabaseConnection(connection_string=db_connection_string)

    try:
        async with DAPClient(base_url=base_url, credentials=credentials) as session:
            await SQLReplicator(session=session, connection=connection).synchronize(
                namespace=namespace, table_name=table_name
            )

    except NonExistingTableError as e:
        result = SyncTableResult.NO_TABLE

    except ValueError as e:
        if "table not initialized" in str(e):
            result = SyncTableResult.INIT_NEEDED

    except Exception as e:
        logger.exception(f"{table_name} sync table exception: {e}")
        result = SyncTableResult.FAILED

    logger.info(f"sync table: {table_name}, result: {result}")

    return {"Table": table_name, "Result": result.value}
