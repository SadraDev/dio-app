import os
from channels.routing import ProtocolTypeRouter, URLRouter
from django.core.asgi import get_asgi_application

import marketdata.routing
from channels.auth import AuthMiddlewareStack

import asyncio
from marketdata.tasks import run_tick_loop

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "core.settings")

django_asgi_app = get_asgi_application()

application = ProtocolTypeRouter({
    "http": django_asgi_app,

    "websocket": AuthMiddlewareStack(
        URLRouter(
            marketdata.routing.websocket_urlpatterns
        )
    ),
})


asyncio.create_task(run_tick_loop())