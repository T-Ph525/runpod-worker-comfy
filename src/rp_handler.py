import runpod
from runpod.serverless.utils import rp_upload
import json
import urllib.request
import urllib.parse
import time
import os
import requests
import base64
import logging
from io import BytesIO
from concurrent.futures import ThreadPoolExecutor
from functools import wraps

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Constants
COMFY_API_AVAILABLE_INTERVAL_MS = 50
COMFY_API_AVAILABLE_MAX_RETRIES = 500
COMFY_POLLING_INTERVAL_MS = int(os.environ.get("COMFY_POLLING_INTERVAL_MS", 250))
COMFY_POLLING_MAX_RETRIES = int(os.environ.get("COMFY_POLLING_MAX_RETRIES", 500))
COMFY_HOST = os.environ.get("COMFY_HOST", "127.0.0.1:8188")
REFRESH_WORKER = os.environ.get("REFRESH_WORKER", "false").lower() == "true"
COMFY_OUTPUT_PATH = os.environ.get("COMFY_OUTPUT_PATH", "/comfyui/output")
BUCKET_ENDPOINT_URL = os.environ.get("BUCKET_ENDPOINT_URL")

# Validate required environment variables
REQUIRED_ENV_VARS = ["COMFY_HOST"]
for var in REQUIRED_ENV_VARS:
    if not os.getenv(var):
        logger.warning(f"Missing environment variable: {var}")

def retry(max_retries=3, delay=2):
    """Retry decorator for API calls."""
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            for attempt in range(max_retries):
                try:
                    return func(*args, **kwargs)
                except requests.RequestException as e:
                    logger.error(f"Attempt {attempt + 1} failed: {e}")
                    time.sleep(delay * (attempt + 1))
            return None
        return wrapper
    return decorator

@retry(max_retries=5, delay=1)
def check_server(url):
    """Check if the server is reachable."""
    response = requests.get(url)
    if response.status_code == 200:
        logger.info("runpod-worker-comfy - API is reachable")
        return True
    return False

def upload_image(image):
    """Upload a single image."""
    name = image["name"]
    blob = base64.b64decode(image["image"])
    files = {"image": (name, BytesIO(blob), "image/png"), "overwrite": (None, "true")}
    response = requests.post(f"http://{COMFY_HOST}/upload/image", files=files)
    return f"Successfully uploaded {name}" if response.status_code == 200 else f"Error uploading {name}"

def upload_images(images):
    """Upload images in parallel."""
    if not images:
        return {"status": "success", "message": "No images to upload", "details": []}
    with ThreadPoolExecutor() as executor:
        responses = list(executor.map(upload_image, images))
    return {"status": "success", "message": "All images uploaded successfully", "details": responses}

def queue_workflow(workflow):
    """Queue a workflow to ComfyUI."""
    data = json.dumps({"prompt": workflow}).encode("utf-8")
    req = urllib.request.Request(f"http://{COMFY_HOST}/prompt", data=data)
    return json.loads(urllib.request.urlopen(req).read())

def get_history(prompt_id):
    """Retrieve history of a given prompt."""
    with urllib.request.urlopen(f"http://{COMFY_HOST}/history/{prompt_id}") as response:
        return json.loads(response.read())

def base64_encode(img_path):
    """Base64 encode an image."""
    with open(img_path, "rb") as image_file:
        return base64.b64encode(image_file.read()).decode("utf-8")

def process_output_images(outputs, job_id):
    """Process output images from ComfyUI."""
    for node_id, node_output in outputs.items():
        if "images" in node_output:
            for image in node_output["images"]:
                output_image_path = os.path.join(COMFY_OUTPUT_PATH, image["subfolder"], image["filename"])
    
    if os.path.exists(output_image_path):
        if BUCKET_ENDPOINT_URL:
            image = rp_upload.upload_image(job_id, output_image_path)
            logger.info("Image uploaded to AWS S3")
        else:
            image = base64_encode(output_image_path)
            logger.info("Image converted to Base64")
        return {"status": "success", "message": image}
    return {"status": "error", "message": f"Image does not exist: {output_image_path}"}

def handler(job):
    """Main job handler."""
    job_input = job["input"]
    workflow = job_input.get("workflow")
    images = job_input.get("images", [])
    if not workflow:
        return {"error": "Missing 'workflow' parameter"}
    
    if not check_server(f"http://{COMFY_HOST}"):
        return {"error": "ComfyUI API is unreachable"}
    
    upload_result = upload_images(images)
    if upload_result["status"] == "error":
        return upload_result
    
    try:
        queued_workflow = queue_workflow(workflow)
        prompt_id = queued_workflow["prompt_id"]
        logger.info(f"Workflow queued with ID {prompt_id}")
    except Exception as e:
        return {"error": f"Error queuing workflow: {str(e)}"}
    
    retries = 0
    try:
        while retries < COMFY_POLLING_MAX_RETRIES:
            history = get_history(prompt_id)
            if prompt_id in history and history[prompt_id].get("outputs"):
                break
            time.sleep(COMFY_POLLING_INTERVAL_MS / 1000)
            retries += 1
        else:
            return {"error": "Max retries reached while waiting for image generation"}
    except Exception as e:
        return {"error": f"Error waiting for image generation: {str(e)}"}
    
    images_result = process_output_images(history[prompt_id].get("outputs"), job["id"])
    return {**images_result, "refresh_worker": REFRESH_WORKER}

if __name__ == "__main__":
    runpod.serverless.start({"handler": handler})
