from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from api.db import get_db
from api.models import AllowanceItem

router = APIRouter()


class AllowanceItemOut(BaseModel):
    item_type: str
    label: str
    unit: str
    per_adult: float
    per_minor: float | None
    per_child: float | None

    model_config = {"from_attributes": True}


class AllowancesResponse(BaseModel):
    last_updated: datetime | None
    items: list[AllowanceItemOut]


@router.get("", response_model=AllowancesResponse)
async def get_allowances(db: Annotated[AsyncSession, Depends(get_db)]):
    result = await db.execute(select(AllowanceItem).order_by(AllowanceItem.id))
    items = result.scalars().all()
    last_updated = max((i.last_updated for i in items), default=None)
    return AllowancesResponse(
        last_updated=last_updated,
        items=[AllowanceItemOut.model_validate(i) for i in items],
    )
