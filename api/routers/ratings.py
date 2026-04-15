import uuid
from datetime import datetime, timedelta, timezone
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import and_, func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from api.auth import get_current_user
from api.db import get_db
from api.models import Rating, Trip, TripPassenger, User
from api.routers.users import get_or_create_user

router = APIRouter()

# Rating window: a trip must have departed before a rating can be submitted,
# and the window closes 7 days after departure.
RATING_WINDOW_DAYS = 7


class RatingCreate(BaseModel):
    rated_user_id: uuid.UUID
    trip_id: uuid.UUID
    score: int = Field(..., ge=1, le=5)
    comment: str | None = Field(None, max_length=500)


class RatingOut(BaseModel):
    id: uuid.UUID
    rater_id: uuid.UUID
    rated_id: uuid.UUID
    trip_id: uuid.UUID | None
    score: int
    comment: str | None
    created_at: datetime

    model_config = {"from_attributes": True}


@router.post("", response_model=RatingOut, status_code=status.HTTP_201_CREATED)
async def create_rating(
    body: RatingCreate,
    firebase_user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    rater = await get_or_create_user(firebase_user, db)

    if rater.id == body.rated_user_id:
        raise HTTPException(status_code=400, detail="Cannot rate yourself")

    # Load the trip
    trip_result = await db.execute(select(Trip).where(Trip.id == body.trip_id))
    trip = trip_result.scalar_one_or_none()
    if not trip:
        raise HTTPException(status_code=404, detail="Trip not found")

    now = datetime.now(timezone.utc)
    if trip.depart_at > now:
        raise HTTPException(status_code=400, detail="Trip has not departed yet")
    if trip.depart_at < now - timedelta(days=RATING_WINDOW_DAYS):
        raise HTTPException(status_code=400, detail="Rating window has closed (7 days after departure)")

    # Rater must be driver or accepted passenger
    is_driver = trip.driver_id == rater.id
    if not is_driver:
        member = await db.execute(
            select(TripPassenger).where(
                and_(
                    TripPassenger.trip_id == body.trip_id,
                    TripPassenger.user_id == rater.id,
                    TripPassenger.status == "accepted",
                )
            )
        )
        if not member.scalar_one_or_none():
            raise HTTPException(status_code=403, detail="You were not part of this trip")

    # Rated user must also have been part of the trip
    rated_result = await db.execute(select(User).where(User.id == body.rated_user_id))
    rated_user = rated_result.scalar_one_or_none()
    if not rated_user:
        raise HTTPException(status_code=404, detail="Rated user not found")

    rated_is_driver = trip.driver_id == body.rated_user_id
    if not rated_is_driver:
        rated_member = await db.execute(
            select(TripPassenger).where(
                and_(
                    TripPassenger.trip_id == body.trip_id,
                    TripPassenger.user_id == body.rated_user_id,
                    TripPassenger.status == "accepted",
                )
            )
        )
        if not rated_member.scalar_one_or_none():
            raise HTTPException(status_code=400, detail="Rated user was not part of this trip")

    # No duplicate ratings
    existing = await db.execute(
        select(Rating).where(
            and_(
                Rating.rater_id == rater.id,
                Rating.rated_id == body.rated_user_id,
                Rating.trip_id == body.trip_id,
            )
        )
    )
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="You already rated this person for this trip")

    rating = Rating(
        rater_id=rater.id,
        rated_id=body.rated_user_id,
        trip_id=body.trip_id,
        score=body.score,
        comment=body.comment,
    )
    db.add(rating)
    await db.flush()  # persist rating so the aggregate query below includes it

    # Recompute avg_rating atomically from all ratings in the DB
    await db.execute(
        update(User)
        .where(User.id == body.rated_user_id)
        .values(
            rating_count=select(func.count(Rating.id))
                .where(Rating.rated_id == body.rated_user_id)
                .scalar_subquery(),
            avg_rating=select(func.avg(Rating.score))
                .where(Rating.rated_id == body.rated_user_id)
                .scalar_subquery(),
        )
    )

    await db.commit()
    await db.refresh(rating)
    return rating
