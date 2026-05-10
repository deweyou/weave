from fastapi import FastAPI

from app.schemas import (
    DiscoverRequest,
    DiscoverResponse,
    EchoRequest,
    EchoResponse,
    HealthResponse,
)


app = FastAPI(title="Weave Agent", version="0.1.0")


@app.get("/health", response_model=HealthResponse)
def health() -> HealthResponse:
    return HealthResponse(status="ok", service="weave-agent", version="0.1.0")


@app.post("/echo", response_model=EchoResponse)
def echo(request: EchoRequest) -> EchoResponse:
    return EchoResponse(message=request.message, received=True)


@app.post("/writing/discover", response_model=DiscoverResponse)
def discover(request: DiscoverRequest) -> DiscoverResponse:
    topic = request.input.strip()
    return DiscoverResponse(
        stage="discover",
        summary=f"用户想写一篇关于 {topic} 的个人表达文章。",
        questions=[
            "你这篇最想写给谁看？",
            "你最想强调的一条判断是什么？",
            "你有没有真实经历让你形成这个判断？",
        ],
    )
