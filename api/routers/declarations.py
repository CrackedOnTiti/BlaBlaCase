import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import and_, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from api.auth import get_current_user
from api.db import get_db
from api.models import Declaration, Trip, TripPassenger
from api.routers.users import get_or_create_user

router = APIRouter()

ALLOWED_ITEM_TYPES = {
    "spirits", "fortified_wine", "still_wine", "beer",
    "cigarettes", "cigarillos", "cigars", "tobacco",
    "perfume", "eau_de_toilette", "coffee", "tea", "goods_value",
}


class DeclarationUpsert(BaseModel):
    item_type: str
    quantity: float


class DeclarationOut(BaseModel):
    user_id: uuid.UUID
    item_type: str
    quantity: float

    model_config = {"from_attributes": True}


async def _assert_trip_member(trip_id: uuid.UUID, user_id: uuid.UUID, db: AsyncSession):
    result = await db.execute(select(Trip).where(Trip.id == trip_id))
    trip = result.scalar_one_or_none()
    if not trip:
        raise HTTPException(status_code=404, detail="Trip not found")
    if trip.driver_id == user_id:
        return
    member = await db.execute(
        select(TripPassenger).where(
            and_(
                TripPassenger.trip_id == trip_id,
                TripPassenger.user_id == user_id,
                TripPassenger.status == "accepted",
            )
        )
    )
    if not member.scalar_one_or_none():
        raise HTTPException(status_code=403, detail="You are not a member of this trip")


@router.get("/trips/{trip_id}/declarations", response_model=list[DeclarationOut])
async def get_declarations(
    trip_id: uuid.UUID,
    firebase_user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    user = await get_or_create_user(firebase_user, db)
    await _assert_trip_member(trip_id, user.id, db)

    result = await db.execute(select(Declaration).where(Declaration.trip_id == trip_id))
    return result.scalars().all()


@router.put("/trips/{trip_id}/declarations", response_model=DeclarationOut)
async def upsert_declaration(
    trip_id: uuid.UUID,
    body: DeclarationUpsert,
    firebase_user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    user = await get_or_create_user(firebase_user, db)
    await _assert_trip_member(trip_id, user.id, db)

    if body.item_type not in ALLOWED_ITEM_TYPES:
        raise HTTPException(status_code=400, detail=f"Unknown item_type: {body.item_type}")
    if body.quantity < 0:
        raise HTTPException(status_code=400, detail="quantity cannot be negative")

    stmt = (
        pg_insert(Declaration)
        .values(trip_id=trip_id, user_id=user.id, item_type=body.item_type, quantity=body.quantity)
        .on_conflict_do_update(
            index_elements=["trip_id", "user_id", "item_type"],
            set_={"quantity": body.quantity},
        )
        .returning(Declaration)
    )
    result = await db.execute(stmt)
    await db.commit()
    return result.scalar_one()
