from django.urls import path

from .views import (
    TripPaymentChannelUpsertView,
    TripPaymentChannelDetailView,
    TripReceiptCreateView,
    TripReceiptDetailView,
    ReceiptAnalyzeOCRView,
    ReceiptConfirmAmountView,
    TripSettlementCreateView,
    TripSettlementCompleteView,
    TripSettlementListView,
    MyPaySettlementListView,
    MyReceiveSettlementListView,
    SettlementDetailView,
    SettlementLinkOpenView,
    SettlementPaySelfView,
    SettlementProofCreateView,
    SettlementConfirmView,
    SettlementDisputeView,
)

urlpatterns = [
    path("trips/<int:trip_id>/payment-channel/", TripPaymentChannelUpsertView.as_view(), name="trip-payment-channel-upsert"),
    path("trips/<int:trip_id>/payment-channel/detail/", TripPaymentChannelDetailView.as_view(), name="trip-payment-channel-detail"),

    path("trips/<int:trip_id>/receipt/", TripReceiptCreateView.as_view(), name="trip-receipt-create"),
    path("trips/<int:trip_id>/receipt/detail/", TripReceiptDetailView.as_view(), name="trip-receipt-detail"),
    path("receipts/<int:receipt_id>/analyze/", ReceiptAnalyzeOCRView.as_view(), name="receipt-analyze-ocr"),
    path("receipts/<int:receipt_id>/confirm-amount/", ReceiptConfirmAmountView.as_view(), name="receipt-confirm-amount"),

    path("trips/<int:trip_id>/settlements/create/", TripSettlementCreateView.as_view(), name="trip-settlement-create"),
    path("trips/<int:trip_id>/settlements/", TripSettlementListView.as_view(), name="trip-settlement-list"),
    path("trips/<int:trip_id>/settlements/complete/", TripSettlementCompleteView.as_view(), name="trip-settlement-complete"),

    path("me/settlements/pay/", MyPaySettlementListView.as_view(), name="my-pay-settlement-list"),
    path("me/settlements/receive/", MyReceiveSettlementListView.as_view(), name="my-receive-settlement-list"),
    path("settlements/<int:settlement_id>/", SettlementDetailView.as_view(), name="settlement-detail"),
    path("settlements/<int:settlement_id>/open-link/", SettlementLinkOpenView.as_view(), name="settlement-open-link"),
    path("settlements/<int:settlement_id>/pay-self/", SettlementPaySelfView.as_view(), name="settlement-pay-self"),
    path("settlements/<int:settlement_id>/proof/", SettlementProofCreateView.as_view(), name="settlement-proof-create"),
    path("settlements/<int:settlement_id>/confirm/", SettlementConfirmView.as_view(), name="settlement-confirm"),
    path("settlements/<int:settlement_id>/dispute/", SettlementDisputeView.as_view(), name="settlement-dispute"),
]