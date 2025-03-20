{
  "title": "RunPod ComfyUI Serverless",
  "description": "Run ComfyUI as a serverless endpoint on RunPod",
  "type": "serverless",
  "category": "image-generation",
  "iconUrl": "https://example.com/icon.png",
  "config": {
    "runsOn": "GPU",
    "containerDiskInGb": 40,
    "networkVolume": true,
    "presets": [
      {
        "name": "Default Configuration",
        "defaults": {
          "MODEL_PATH": "/runpod-volume/models",
          "CUSTOM_NODES_PATH": "/runpod-volume/custom_nodes",
          "STATIC_1": "default_value_1",
          "STRING_1": "default_value_2"
        }
      }
    ],
    "env": [
      {
        "key": "MODEL_PATH",
        "value": "/runpod-volume/models"
      },
      {
        "key": "CUSTOM_NODES_PATH",
        "value": "/runpod-volume/custom_nodes"
      },
      {
        "key": "STATIC_VAR",
        "value": "static_value"
      },
      {
        "key": "COMFY_POLLING_INTERVAL_MS",
        "input": {
          "name": "Polling Interval",
          "type": "integer",
          "description": "Interval for polling jobs (ms)",
          "default": 500
        }
      },
      {
        "key": "COMFY_POLLING_MAX_RETRIES",
        "input": {
          "name": "Polling Max Retries",
          "type": "integer",
          "description": "Maximum retries for polling jobs",
          "default": 3
        }
      },
      {
        "key": "SERVE_API_LOCALLY",
        "input": {
          "name": "Serve API Locally",
          "type": "boolean",
          "description": "Enable local API testing",
          "default": false
        }
      }
    ]
  }
}
