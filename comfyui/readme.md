# Comfy UI SM120

The most powerful and modular diffusion model GUI, api and backend with a graph/nodes interface. https://github.com/comfyanonymous/ComfyUI

## Run

### Docker

See https://github.com/hartmark/sd-rocm/blob/main/docker-compose.yml

Persistence (files):
```bash
-e PERSISTENCE_PATH=/data
-v $(pwd)/data:/data
```

Persistence (venv):
```bash
-e VENV_NAME=venv
```

Behavior:
- Creates a Python virtual environment
  - With persistence: /data/<venv>
  - Without: /comfyui/<venv>


### Kubernetes

Helm chart and samples [mixa3607 charts](https://github.com/mixa3607/charts)

## Build

See build vars in `./env.sh`. You also may use presetis `./preset.*.sh`. Exec `./build-and-push.comfyui.sh`:

```bash
$ . preset.v0.21.1-cuda13.0-cudnn9.sh
$ ./build-and-push.comfyui.sh 
#0 building with "remote" instance using remote driver
#...............
#14 DONE 583.8s
```
