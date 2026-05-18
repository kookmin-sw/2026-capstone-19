import json
from channels.generic.websocket import AsyncWebsocketConsumer


# chat/consumers.py 맨 아래에 추가하거나 trips/consumers.py에 작성
class TripConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        self.trip_id = self.scope['url_route']['kwargs']['trip_id']
        self.group_name = f"trip_{self.trip_id}"

        await self.channel_layer.group_add(self.group_name, self.channel_name)
        await self.accept()

    async def disconnect(self, close_code):
        await self.channel_layer.group_discard(self.group_name, self.channel_name)

    # 🚀 핵심: views.py에서 보낸 'trip_update' 타입을 처리하는 함수
    async def trip_update(self, event):
        # event 딕셔너리 내용을 그대로 Flutter 앱으로 전송
        await self.send(text_data=json.dumps(event))