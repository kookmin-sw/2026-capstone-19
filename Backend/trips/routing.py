# trips/routing.py
from django.urls import path
from . import consumers

websocket_urlpatterns = [
    # Flutter: 'ws://10.0.2.2:8000/ws/trip/<trip_id>/'
    path('ws/trip/<int:trip_id>/', consumers.TripConsumer.as_asgi()),
]