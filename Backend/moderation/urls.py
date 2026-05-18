from django.urls import path
from . import views

urlpatterns = [
    path('trust-score-logs/', views.TrustScoreLogView.as_view(), name='trust-score-logs'),
    path('report/', views.ReportUserView.as_view(), name='report-user'),
    path('reviews/', views.TripReviewCreateView.as_view(), name='trip-reviews'),
]