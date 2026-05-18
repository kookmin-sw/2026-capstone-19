from datetime import timedelta

from django.core.management.base import BaseCommand
from django.db.models import Count
from django.utils import timezone

from chat.models import ChatRoom


class Command(BaseCommand):
    help = "Delete archived chat rooms for completed trips after the retention period."

    def add_arguments(self, parser):
        parser.add_argument(
            "--days",
            type=int,
            default=30,
            help="Retention period in days after chat room expires_at. Default is 30.",
        )
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="Show deletion target count without deleting data.",
        )

    def handle(self, *args, **options):
        retention_days = options["days"]
        dry_run = options["dry_run"]

        cutoff = timezone.now() - timedelta(days=retention_days)

        target_rooms = (
            ChatRoom.objects
            .filter(
                is_archived=True,
                expires_at__isnull=False,
                expires_at__lte=cutoff,
                trip__status="COMPLETED",
            )
            .annotate(message_count=Count("messages"))
        )

        room_count = target_rooms.count()
        message_count = sum(room.message_count for room in target_rooms)

        if dry_run:
            self.stdout.write(
                self.style.WARNING(
                    f"[DRY RUN] {room_count} chat rooms and "
                    f"{message_count} messages would be deleted."
                )
            )
            return

        deleted_count, deleted_details = target_rooms.delete()

        self.stdout.write(
            self.style.SUCCESS(
                f"Deleted {room_count} chat rooms and approximately "
                f"{message_count} messages. Total deleted objects: {deleted_count}."
            )
        )