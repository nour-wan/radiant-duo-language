from django.core.management.base import BaseCommand

from apps.store import fx


class Command(BaseCommand):
    help = "Read today's USD rate in Damascus from sp-today.com (run every 15 minutes by cron)."

    def handle(self, *args, **opts):
        entry, problem = fx.update_from_source()
        if entry is None:
            self.stderr.write(f"failed: {problem}")
        elif problem:
            self.stdout.write(f"held back (big change): buy {entry.buy} / sell {entry.sell}")
        else:
            self.stdout.write(f"ok: buy {entry.buy} / sell {entry.sell}")
