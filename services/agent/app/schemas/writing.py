from typing import Literal

from pydantic import BaseModel, Field, field_validator


class HealthResponse(BaseModel):
    status: Literal["ok"]
    service: str
    version: str


class EchoRequest(BaseModel):
    message: str = Field(min_length=1)


class EchoResponse(BaseModel):
    message: str
    received: bool


class DiscoverRequest(BaseModel):
    input: str = Field(min_length=1)

    @field_validator("input")
    @classmethod
    def input_must_not_be_blank(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("input must not be blank")
        return value


class DiscoverResponse(BaseModel):
    stage: Literal["discover"]
    summary: str
    questions: list[str]
