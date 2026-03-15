"""Seed script to populate office properties in the database.

Usage:
    cd backend/
    uv run python seed_offices.py
"""

import logging

from sqlmodel import select, Session

from flxo.models.office import Office
from flxo.models.seat import Seat
from flxo.services.database import engine


logger = logging.getLogger(__name__)

OFFICES = [
    {
        "name": "Wojo Paris",
        "address": "Paris",
        "desk_count": 6,
        "properties": {
            "logo_url": "/wojo-logo.png",
            "floor_plan_url": "/wojo-paris.svg",
        },
    },
    {
        "name": "Vates Grenoble",
        "address": "Grenoble",
        "desk_count": 10,
        "properties": {"floor_plan_url": "/open-space-100.svg"},
    },
    {
        "name": "Vates Cambridge",
        "address": "Cambridge",
        "desk_count": 10,
        "properties": {},
    },
]


def seed() -> None:
    logging.basicConfig(level=logging.INFO)
    with Session(engine) as session:
        for office_data in OFFICES:
            desk_count = office_data.pop("desk_count", 0)
            existing = session.exec(
                select(Office).where(Office.name == office_data["name"])
            ).first()
            if existing:
                existing.properties = {
                    **existing.properties,
                    **office_data["properties"],
                }
                existing.address = office_data["address"]
                session.add(existing)
                office_obj = existing
                logger.info("Updated office: %s", existing.name)
            else:
                office_obj = Office(**office_data)
                session.add(office_obj)
                session.flush()
                logger.info("Created office: %s", office_obj.name)

            # Create missing seats
            existing_seats = session.exec(
                select(Seat).where(Seat.office_id == office_obj.id)
            ).all()
            existing_names = {s.name for s in existing_seats}
            for i in range(1, desk_count + 1):
                name = f"desk{i}"
                if name not in existing_names:
                    session.add(Seat(name=name, office_id=office_obj.id))
                    logger.info("  Created seat: %s", name)

        session.commit()


if __name__ == "__main__":
    seed()
