import os
import boto3
from fastapi import FastAPI, UploadFile, File
from dotenv import load_dotenv
from botocore.config import Config

load_dotenv()

app = FastAPI()

# Initialize S3 Client for Supabase
s3_client = boto3.client(
    's3',
    endpoint_url=os.getenv("SUPABASE_S3_ENDPOINT"),
    aws_access_key_id=os.getenv("SUPABASE_S3_ACCESS_KEY"),
    aws_secret_access_key=os.getenv("SUPABASE_S3_SECRET_KEY"),
    region_name=os.getenv("SUPABASE_S3_REGION"),
    config=Config(s3={'addressing_style': 'path'})
)

BUCKET_NAME = os.getenv("SUPABASE_BUCKET_NAME")

@app.post("/upload/")
async def upload_file(file: UploadFile = File(...)):
    try:
        # Upload to Supabase Storage via S3 protocol
        s3_client.upload_fileobj(
            file.file, 
            BUCKET_NAME, 
            file.filename,
            ExtraArgs={"ContentType": file.content_type}
        )
        return {"message": f"Successfully uploaded {file.filename}"}
    except Exception as e:
        return {"error": str(e)}

@app.get("/files/")
async def list_files():
    response = s3_client.list_objects_v2(Bucket=BUCKET_NAME)
    files = [obj['Key'] for obj in response.get('Contents', [])]
    return {"files": files}