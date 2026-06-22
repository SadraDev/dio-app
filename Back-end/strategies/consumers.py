import json
from channels.generic.websocket import AsyncWebsocketConsumer
from .manager import WorkerManager
from asgiref.sync import sync_to_async

class StrategyConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        self.group_name = "strategy_updates"
        await self.channel_layer.group_add(self.group_name, self.channel_name)
        await self.accept()

        # Push immediate snapshot upon connection so the app loads instantly
        snapshot = await self.get_snapshot()
        await self.send(text_data=json.dumps({
            "type": "snapshot", 
            "data": snapshot
        }))

    async def disconnect(self, close_code):
        await self.channel_layer.group_discard(self.group_name, self.channel_name)

    async def strategy_update(self, event):
        # Triggered by the WorkerManager broadcast
        await self.send(text_data=json.dumps({
            "type": "update",
            "data": event["data"]
        }))

    @sync_to_async
    def get_snapshot(self):
        return WorkerManager.instance().snapshot()