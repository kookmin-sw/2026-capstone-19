"""
URL configuration for config project.

The `urlpatterns` list routes URLs to views. For more information please see:
    https://docs.djangoproject.com/en/6.0/topics/http/urls/
Examples:
Function views
    1. Add an import:  from my_app import views
    2. Add a URL to urlpatterns:  path('', views.home, name='home')
Class-based views
    1. Add an import:  from other_app.views import Home
    2. Add a URL to urlpatterns:  path('', Home.as_view(), name='home')
Including another URLconf
    1. Import the include() function: from django.urls import include, path
    2. Add a URL to urlpatterns:  path('blog/', include('blog.urls'))
"""
from django.contrib import admin
from django.urls import path, include  # 1. include를 여기에 꼭 추가해야 합니다!
from django.conf import settings
from django.conf.urls.static import static

urlpatterns = [
    # 2. admin.site.view가 아니라 admin.site.urls가 맞습니다.
    path('admin/', admin.site.urls),

    # 3. 각 앱의 상세 지도로 연결
    path('api/accounts/', include('accounts.urls')),
    path('api/trips/', include('trips.urls')),
    path('api/users/', include('accounts.urls')),
    path('api/moderation/', include('moderation.urls')),
    path('', include('chat.urls')),
    #path('/api/trips/{tripId}/join/', include('trips.urls')),
    path('api/settlements/', include('settlements.urls')),
]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
