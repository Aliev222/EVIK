# EVIK / Avro — COMPLETE FUNCTION MAP

Scope: client app + driver app (Flutter frontend). Read-only audit. All paths relative to `frontend/`.
Amounts in rubles unless noted. Lines verified against current sources.

## Flag legend
- [SERVER-OK]      data correctly comes from backend
- [CLIENT-DECIDES] client computes/decides something that should be server-authoritative
- [HARDCODED]      value baked into the app that should come from server/config
- [LOCAL-ONLY]     stored only on device (risk noted where applicable)

Server API map referenced (backend/): /orders, /orders/active, /orders/{id}/*, /pricing/*, /payments/*,
/drivers/*, /driver/current-offer, /auth/*, /reviews, /service-areas/check, /ws/orders, /routing/*.

---

# PART A — CLIENT APP FUNCTION REGISTRY

## A1. Auth / OTP
| Function | File:Line | What it does | Data source | Flag |
|---|---|---|---|---|
| signInWithPhone | features/auth/presentation/providers/auth_provider.dart:142 | Requests OTP | POST /auth/otp/request | [SERVER-OK] |
| verifySmsCode | features/auth/presentation/providers/auth_provider.dart:190 | Verifies 6-digit code, logs in | POST /auth/otp/verify | [SERVER-OK] |
| resendSmsCode | features/auth/presentation/providers/auth_provider.dart:265 | Resends OTP | POST /auth/otp/request | [SERVER-OK] |
| refreshAccessToken | features/auth/presentation/providers/auth_provider.dart:329 | Rotates tokens | POST /auth/refresh | [SERVER-OK] |
| _restoreSession | features/auth/presentation/providers/auth_provider.dart:402 | Restores session on launch | /auth/me + local storage | [SERVER-OK] |
| _saveSession | features/auth/presentation/providers/auth_provider.dart:486 | Persists tokens | Secure storage (keychain) | [LOCAL-ONLY] (tokens only, standard) |
| _registerFcmToken | features/auth/presentation/providers/auth_provider.dart:529 | Push token | POST /devices/fcm-token | [SERVER-OK] |
| _normalizePhone | features/auth/presentation/providers/auth_provider.dart:594 | Forces +7 format client-side | Local logic | [CLIENT-DECIDES] |
| _deriveUserID | features/auth/presentation/providers/auth_provider.dart:612 | Builds user id as 'u'+digits | Hardcoded formula | [HARDCODED] |
| _isPhoneValid | features/auth/presentation/screens/auth_screen.dart:136 | 11-digit, starts with 7 | Local regex | [HARDCODED] |
| _sendSmsCode | features/auth/presentation/screens/auth_screen.dart:177 | Triggers OTP flow | calls authProvider | [CLIENT-DECIDES] |
| _verifySmsCode | features/auth/presentation/screens/sms_verification_screen.dart:183 | Submits code | calls authProvider | [CLIENT-DECIDES] |
| _resendCode (75s) | features/auth/presentation/screens/sms_verification_screen.dart:175 | Resend countdown | Local timer | [CLIENT-DECIDES] |

## A2. Home screen
| Function | File:Line | What it does | Data source | Flag |
|---|---|---|---|---|
| _initLocation | features/client/presentation/screens/client_home_screen.dart:39 | Permission + GPS fix | Device GPS | [LOCAL-ONLY] |
| Service area check | features/client/presentation/screens/client_home_screen.dart:70-72,220,226-228 | Gate "call tow truck" | GET /service-areas/check | [SERVER-OK] |
| _showServiceDisabledDialog | client_home_screen.dart:82 | Location-off dialog | Local | [CLIENT-DECIDES] |
| _showDeniedForeverDialog | client_home_screen.dart:134 | Open settings dialog | Local | [CLIENT-DECIDES] |
| _openPickupSelection | client_home_screen.dart:187 | Starts order flow | Local nav | [CLIENT-DECIDES] |
| _showComingSoon | client_home_screen.dart:192 | "Coming soon" snackbar | Hardcoded | [HARDCODED] |
| SOS slider | client_home_screen.dart:255-259 | Slide-to-confirm SOS | "coming soon" | [HARDCODED] |
| Quick services grid | client_home_screen.dart:508-534 | 4 services (tire/battery/electrician/fuel) | Hardcoded list | [HARDCODED] |
| Reverse geocode | via OpenStreetMapService | Coord->address | OSM Nominatim | [SERVER-OK] |

## A3. Order creation (type, wheels, comment, price)
| Function | File:Line | What it does | Data source | Flag |
|---|---|---|---|---|
| startOrderFlow / resetFlow | order_flow_provider.dart:41,145 | Flow lifecycle | Local | [CLIENT-DECIDES] |
| setPickup/DestinationLocation | order_flow_provider.dart:158,163 | Stores coords | Local | [CLIENT-DECIDES] |
| selectVehicleType | order_flow_provider.dart:169 | Light/SUV/minibus | Hardcoded enum | [HARDCODED] |
| selectTowTruckType | order_flow_provider.dart:178 | Winch/platform/manipulator | Hardcoded enum | [HARDCODED] |
| _calculateDistanceAndPrice | order_flow_provider.dart:478 | Haversine distance | Local formula | [LOCAL-ONLY] |
| _updatePrice | order_flow_provider.dart:495 | Server price quote | POST /pricing/calculate | [SERVER-OK] |
| localPriceFor | order_flow_provider.dart:90 | base + perKm*distance | Local formula | [CLIENT-DECIDES] |
| _loadTariffs | order_flow_provider.dart:72 | Fetch tariffs | GET /pricing/tariffs | [SERVER-OK] |
| goToDriverSearch | order_flow_provider.dart:110 | Create order + search | POST /orders | [SERVER-OK] |
| _createOrderWithPaymentFlow | order_flow_provider.dart:255 | Order creation | POST /orders | [SERVER-OK] |
| Blocked wheels stepper | vehicle_selection_screen.dart:356-403 | 0-4 wheels | Local state | [CLIENT-DECIDES] |
| Payment method selector | vehicle_selection_screen.dart:672-774 | Cash/card | Local state | [CLIENT-DECIDES] |
| Comment field | vehicle_selection_screen.dart:776-813 | Client comment | Local input | [CLIENT-DECIDES] |
| _editComment | vehicle_selection_screen.dart:133-190 | Comment bottom sheet | Local modal | [CLIENT-DECIDES] |
| Price per tow type | vehicle_selection_screen.dart:532-574 | Shows price per type | POST /pricing/calculate OR local | [SERVER-OK] mixed |
| estimateRub | features/order/domain/entities/tariff.dart:16 | base + perKm*distance | Local formula | [CLIENT-DECIDES] |
| createOrder / calculatePrice | http_order_repository.dart:31,72 | Server calls | POST /orders, /pricing/calculate | [SERVER-OK] |
| watchOrder (poll 2s) | http_order_repository.dart:212 | Order status poll | GET /orders/{id} | [CLIENT-DECIDES] |

## A4. Search / dispatch view
| Function | File:Line | What it does | Data source | Flag |
|---|---|---|---|---|
| _initializeRealTimeService | driver_search_screen.dart:35 | WS connect as client | /ws/orders | [SERVER-OK] |
| Create order via WS | driver_search_screen.dart:65-78 | createOrder message | WS->POST /orders | [SERVER-OK] |
| Client location updates (10s) | driver_search_screen.dart:89-114 | Sends GPS | WS client_location | [SERVER-OK] |
| driverFound / noDriversAvailable | driver_search_screen.dart:47-62 | Listener | WS stream | [SERVER-OK] |
| Cross-city surcharge dialog | driver_search_screen.dart:127-253 | Extra fee dialog | Order surcharge data | [SERVER-OK] |
| Search timer | driver_search_screen.dart:265,367 | MM:SS elapsed | Local timer | [LOCAL-ONLY] |
| Cancel search | driver_search_screen.dart:418 | Cancel order | POST /orders/{id}/cancel | [SERVER-OK] |
| _startOrderPolling (2s) | order_flow_provider.dart:329 | Poll order | GET /orders/{id} | [CLIENT-DECIDES] |
| _fetchDriverProfile | order_flow_provider.dart:402 | Assigned driver | GET /drivers/{id} | [SERVER-OK] |

## A5. Tracking (driver marker, ETA, route)
| Function | File:Line | What it does | Data source | Flag |
|---|---|---|---|---|
| _initializeRealTimeTracking | tracking_screen.dart:96 | WS driver location stream | /ws/orders | [SERVER-OK] |
| Driver marker animation | tracking_screen.dart:76-94,356-407 | Interpolation + rotation | Local animation | [CLIENT-DECIDES] |
| Bearing animation | tracking_screen.dart:117-129 | Truck icon rotation | Local animation | [CLIENT-DECIDES] |
| Route calculation | tracking_screen.dart:145-199 | Driver->pickup/dest route | OSRM API | [SERVER-OK] |
| Route refresh (100m/30s) | tracking_screen.dart:201-217 | Re-route trigger | Local distance calc | [CLIENT-DECIDES] |
| ETA calculation | tracking_screen.dart:238-247 | ETA display | Hardcoded "5-10 мин" | [HARDCODED] |
| Progress tracker | tracking_screen.dart:560-628 | Accepted->Arrived->Loading | Order status | [SERVER-OK] |
| Driver info card | tracking_screen.dart:542,684-746 | Name/vehicle/rating | Order data | [SERVER-OK] |
| _establishWsTracking | tracking_screen.dart:131 | startTracking | realTimeDriverProvider | [SERVER-OK] |

## A6. Driver info card
| Function | File:Line | What it does | Data source | Flag |
|---|---|---|---|---|
| Driver profile display | driver_info_screen.dart:77,134 | Name/vehicle/phone | orderFlowProvider.assignedDriver (GET /drivers/{id}) | [SERVER-OK] |
| Live driver location | driver_info_screen.dart:66-74 | Map marker | WS driver_location | [SERVER-OK] |
| _makePhoneCall | driver_info_screen.dart:24 | Phone dialer | url_launcher | [LOCAL-ONLY] |
| _sendMessage | driver_info_screen.dart:29 | SMS app | url_launcher | [LOCAL-ONLY] |
| Track on map | driver_info_screen.dart:294 | To tracking | Navigation | [CLIENT-DECIDES] |
| Use real driver data (comment) | driver_info_screen.dart:76 | replaces hardcoded | GET /drivers/{id} | [SERVER-OK] |

## A7. Payment method + confirm
| Function | File:Line | What it does | Data source | Flag |
|---|---|---|---|---|
| Load wallet/cards | client_wallet_screen.dart:29-44,72 | Fetch cards+payments | GET /payments/wallet | [SERVER-OK] |
| Add card (YooKassa) | client_wallet_screen.dart:240-260 | Hosted card add | POST /client/payment-methods/init | [SERVER-OK] |
| Set default card | client_wallet_screen.dart:187 | Default card | POST /payments/cards/{id}/default | [SERVER-OK] |
| Delete card | client_wallet_screen.dart:214 | Remove card | DELETE /payments/cards/{id} | [SERVER-OK] |
| createOrderPayment | http_order_repository.dart:91 | Create payment | POST /orders/{id}/payments | [SERVER-OK] |
| confirmPayment | http_order_repository.dart:279 | Confirm payment | POST /orders/{id}/confirm-payment | [SERVER-OK] |
| updatePaymentMethod | http_order_repository.dart:289 | Cash/card switch | PATCH /orders/{id}/payment-method | [SERVER-OK] |
| getOrderPaymentStatus | http_order_repository.dart:103 | Poll payment | GET /orders/{id}/payment-status | [SERVER-OK] |
| payment_confirmation_screen | features/order/screens/payment_confirmation_screen.dart:201 | Acquiring stub TODO | Local | [GAP] |

## A8. Review
| Function | File:Line | What it does | Data source | Flag |
|---|---|---|---|---|
| _submitRating | driver_rating_screen.dart:30 | Create review | POST /reviews | [SERVER-OK] |
| Star selector | driver_rating_screen.dart:292 | 5-star tap | Local state | [CLIENT-DECIDES] |
| Rating labels | driver_rating_screen.dart:410-425 | "Плохо".."Отлично" | Hardcoded map | [HARDCODED] |
| Comment field | driver_rating_screen.dart:332 | Review text | Local input | [CLIENT-DECIDES] |
| Load order+driver | order_review_screen.dart:40 | Review from history | GET /orders/{id}, /drivers/{id} | [SERVER-OK] |
| createReview | http_review_repository.dart:27 | Post review | POST /reviews | [SERVER-OK] |
| getDriverReviews / getOrderReview | http_review_repository.dart:39,49 | Fetch reviews | GET /drivers/{id}/reviews, /orders/{id}/review | [SERVER-OK] |

## A9. SOS
| Function | File:Line | What it does | Data source | Flag |
|---|---|---|---|---|
| Offline SOS screen | shared/widgets/offline_sos_screen.dart:13-339 | Call 112/102/103, copy coords | Device GPS + tel: links | [LOCAL-ONLY] |
| _call / _copyCoordinates | offline_sos_screen.dart:55,59 | Emergency actions | url_launcher / clipboard | [LOCAL-ONLY] |
| _retry (4s) | offline_sos_screen.dart:74 | Re-login | authProvider.retrySession | [CLIENT-DECIDES] |
| SOS slider (home) | client_home_screen.dart:255-259 | "coming soon" | Hardcoded | [HARDCODED] |

## A10. Active-order restore
| Function | File:Line | What it does | Data source | Flag |
|---|---|---|---|---|
| restoreActiveFlow | order_flow_provider.dart:537-588 | Restore on relaunch | SharedPreferences + GET /orders/{id} | [SERVER-OK] |
| _persistActiveOrder | order_flow_provider.dart:626 | Save active order id | SharedPreferences | [LOCAL-ONLY] (persistence, correct) |
| _refreshActiveOrder | order_flow_provider.dart:337 | Latest state | GET /orders/{id} | [SERVER-OK] |
| _applyBackendOrderUpdate | order_flow_provider.dart:347 | WS->flow transition | WS + order state | [SERVER-OK] |
| _generateIdempotencyKey | order_flow_provider.dart:450 | UUID for create | Local UUID | [CLIENT-DECIDES] |

## A11. History
| Function | File:Line | What it does | Data source | Flag |
|---|---|---|---|---|
| _loadOrders | client_history_screen.dart:39 | Order list | GET /orders | [SERVER-OK] |
| Order card | client_history_screen.dart:319-381 | Date/price/status/route | Order object | [SERVER-OK] |
| Status badge colors | client_history_screen.dart:341-364 | Yellow/green/red/blue | Hardcoded map | [HARDCODED] |
| Review section | client_history_screen.dart:255-260,392 | Existing/leave review | GET /orders/{id}/review | [SERVER-OK] |
| Month names | client_history_screen.dart:383-389 | RU abbrevs | Hardcoded list | [HARDCODED] |

## A12. Profile / settings
| Function | File:Line | What it does | Data source | Flag |
|---|---|---|---|---|
| User info | client_profile_screen.dart:43-90 | Name/phone/badge | authProvider.user | [SERVER-OK] |
| Notifications tile | client_profile_screen.dart:96 | "coming soon" | Hardcoded | [HARDCODED] |
| Emergency contacts tile | client_profile_screen.dart:103 | 112/ГИБДД/Ambulance | Hardcoded | [HARDCODED] |
| Support tile | client_profile_screen.dart:110 | chat/phone/email | Hardcoded | [HARDCODED] |
| Payment methods tile | client_profile_screen.dart:117 | To wallet | Nav | [CLIENT-DECIDES] |
| Sign out | client_profile_screen.dart:124-166 | Confirm + logout | authProvider.signOut | [SERVER-OK] |
| _showFeatureSheet | client_profile_screen.dart:203 | "coming soon" sheet | Hardcoded | [HARDCODED] |


# PART B — DRIVER APP FUNCTION REGISTRY

## B1. Auth / onboarding
| Function | File:Line | What it does | Data source | Flag |
|---|---|---|---|---|
| _openDocumentPicker | driver/presentation/screens/driver_documents_screen.dart:148 | Camera/gallery pick | ImagePicker (local) | [LOCAL-ONLY] |
| _DocumentCard | driver_documents_screen.dart:173 | Upload status | Local docs map | [CLIENT-DECIDES] |
| DocumentCameraScreen | document_camera_screen.dart:10 | Source selection | Local | [CLIENT-DECIDES] |
| _submit | driver_profile_setup_screen.dart:311 | Submit verification | POST /driver-verifications | [SERVER-OK] |
| updateProfileDraft | driver_onboarding_provider.dart:108 | Local draft | Local state | [CLIENT-DECIDES] |
| pickDocument | driver_onboarding_provider.dart:123 | Validate+store image | ImagePicker+local | [CLIENT-DECIDES] |
| pickSelfie | driver_onboarding_provider.dart:175 | Selfie (700x700,45KB) | Camera | [CLIENT-DECIDES] |
| submitForModeration | driver_onboarding_provider.dart:236 | Upload+submit | POST /driver-documents/uploads, /driver-verifications | [SERVER-OK] |
| watchDriverModerationProvider | driver_moderation_provider.dart:71 | Stream status | MOCKED approved | [HARDCODED] GAP |
| ModerationWaitingScreen | moderation_waiting_screen.dart:5 | Static "submitted" | Hardcoded text | [HARDCODED] |
| DriverModerationScreen | driver_moderation_screen.dart:9 | Status display | GET /drivers/{id}/verification-status | [SERVER-OK] |

## B2. Online/offline toggle
| Function | File:Line | What it does | Data source | Flag |
|---|---|---|---|---|
| goOnline | new_driver_provider.dart:184 | Online + WS + tracking | POST /drivers/{id}/status | [SERVER-OK] |
| goOffline | new_driver_provider.dart:220 | Offline + WS close | POST /drivers/{id}/status | [SERVER-OK] |
| toggleOnlineStatus (legacy) | driver_status_provider.dart:150 | Toggle + location | POST /drivers/{id}/status | [SERVER-OK] |
| OnlineStatusToggle | online_status_toggle.dart:5 | UI switch | Props | [CLIENT-DECIDES] |
| Offline confirm dialog | online_status_toggle.dart:79-116 | Confirm going offline | Local dialog | [CLIENT-DECIDES] |
| _formatDuration | online_status_toggle.dart:122 | Online duration | Computed | [CLIENT-DECIDES] |
| _initLocation | new_driver_home_screen.dart:71 | Permission + GPS | Device GPS | [LOCAL-ONLY] |
| _buildOfflineView | new_driver_home_screen.dart:243 | "Start work" view | Local + profile API | [CLIENT-DECIDES] |
| _buildOnlineView | new_driver_home_screen.dart:376 | Map + available orders | WS + GPS | [SERVER-OK] |

## B3. Incoming offer
| Function | File:Line | What it does | Data source | Flag |
|---|---|---|---|---|
| _startOfferListener | new_driver_provider.dart:278 | WS offers | /ws/orders | [SERVER-OK] |
| _loadCurrentOffer | new_driver_provider.dart:404 | Poll fallback | GET /driver/current-offer | [SERVER-OK] |
| _IncomingOrderSheet | new_driver_home_screen.dart:761 | Details + accept/decline | WS offer object | [SERVER-OK] |
| Offer countdown | new_driver_home_screen.dart:163-211 | expiresAt timer | Server expiresAt + local timer | [SERVER-OK]+[CLIENT-DECIDES] |
| _syncRoutePreview | new_driver_home_screen.dart:486 | OSM route preview | OSRM API | [SERVER-OK] |
| AvailableOrderCard | available_order_card.dart:7 | Offer card | Server object | [SERVER-OK] |

## B4. Accept → arrive → loaded → complete (status ladder)
| Function | File:Line | What it does | Data source | Flag |
|---|---|---|---|---|
| acceptOrder | new_driver_provider.dart:251 | Accept offer | POST /orders/{id}/accept | [SERVER-OK] |
| declineOrder | new_driver_provider.dart:270 | Decline offer | POST /orders/{id}/decline | [SERVER-OK] |
| arrivedAtClient | new_driver_provider.dart:301 | Status -> arrived | POST /orders/{id}/status | [SERVER-OK] |
| startDrivingToDestination | new_driver_provider.dart:321 | Status -> in_progress (loaded) | POST /orders/{id}/status | [SERVER-OK] |
| completeOrder | new_driver_provider.dart:343 | Finalize + price | POST /orders/{id}/finalize | [SERVER-OK] |
| _updateOrderStatus | new_driver_provider.dart:390 | Generic status | POST /orders/{id}/status | [SERVER-OK] |
| _startPaymentPolling (3s) | new_driver_provider.dart:365 | Payment poll | GET /orders/{id} | [CLIENT-DECIDES] |
| _handlePrimaryAction | active_order_screen.dart:156 | Status buttons | Provider -> API | [SERVER-OK] |
| _ActiveOrderBottomSheet | active_order_screen.dart:328 | Client info + actions | Server order | [SERVER-OK] |
| Slide to complete | active_order_screen.dart:433-438 | Gesture -> finalize | Gesture + API | [CLIENT-DECIDES] |
| _openNavigation | active_order_screen.dart:184 | External nav app | OS apps | [LOCAL-ONLY] |
| DriverActiveOrderCard (legacy) | active_order_card.dart:10 | Status buttons | Server order | [SERVER-OK] |

## B5. Location sending
| Function | File:Line | What it does | Data source | Flag |
|---|---|---|---|---|
| checkPermissions | driver_location_service.dart:10 | Service+permission | OS | [LOCAL-ONLY] |
| getCurrentPosition | driver_location_service.dart:33 | One-shot GPS | Geolocator | [LOCAL-ONLY] |
| startLocationTracking | driver_location_service.dart:38 | 10s/10m stream | Geolocator | [LOCAL-ONLY] |
| updateLocation | driver_status_provider.dart:208 | Send to server | POST /drivers/{id}/location (WS) | [SERVER-OK] |
| WS location_update | realtime_location_service.dart:138-205 | rate-limited 2s | /ws/orders | [SERVER-OK] |
| updateDriverStatus | http_driver_repository.dart:88-94 | Online+loc | POST /drivers/{id}/status | [SERVER-OK] |

## B6. Earnings
| Function | File:Line | What it does | Data source | Flag |
|---|---|---|---|---|
| EarningsCard | earnings_card.dart:8 | Today earnings | EarningsStats (API) | [SERVER-OK] |
| DriverEarningsScreen | driver_earnings_screen.dart:14 | Wallet management | driverWalletProvider | [SERVER-OK] |
| _AvailableBalanceCard | driver_earnings_screen.dart:163 | Withdrawable balance | GET /driver/wallet | [SERVER-OK] |
| _confirmPayout | driver_earnings_screen.dart:263 | Request full payout | POST /driver/payouts/request | [SERVER-OK] |
| Payout methods screen | driver_earnings_screen.dart:322 | Manage methods | GET /driver/payout-methods | [SERVER-OK] |
| Add payout method | driver_earnings_screen.dart:380 | Add card/SBP | POST /driver/payout-methods | [SERVER-OK] |
| Transactions screen | driver_earnings_screen.dart:629 | Tx history | GET /driver/wallet/transactions | [SERVER-OK] |
| refresh | driver_wallet_provider.dart:80 | Wallet+payout+sub | GET /driver/wallet etc | [SERVER-OK] |
| requestFullPayout | driver_wallet_provider.dart:101 | Payout | POST /driver/payouts/request | [SERVER-OK] |
| addPayoutMethod | driver_wallet_provider.dart:122 | Save method | POST /driver/payout-methods | [SERVER-OK] |
| createSubscriptionPayment | driver_wallet_provider.dart:151 | Subscription pay | POST /driver/subscription/payment | [SERVER-OK] |
| driver_earnings_provider.dart:85-95 | DriverStats /100 TODO | Rub conversion | Local | [CLIENT-DECIDES] |

## B7. Subscription
| Function | File:Line | What it does | Data source | Flag |
|---|---|---|---|---|
| DriverSubscriptionScreen | driver_earnings_screen.dart:534 | Avro Pro plans | GET /driver/subscription/status | [SERVER-OK] |
| createSubscriptionPayment | driver_wallet_provider.dart:151 | Pay plan | POST /driver/subscription/payment | [SERVER-OK] |
| Subscription status | driver_wallet_provider.dart:80 | Active/expired/none | GET /driver/subscription/status | [SERVER-OK] |

## B8. Profile / docs
| Function | File:Line | What it does | Data source | Flag |
|---|---|---|---|---|
| driverProfileProvider | driver_profile_screen.dart:14 | Profile data | GET /drivers/{id} | [SERVER-OK] |
| _buildProfileContent | driver_profile_screen.dart:142 | Info/vehicle/stats | Driver entity | [SERVER-OK] |
| Menu items | driver_profile_screen.dart:294-358 | docs/notifications/pay/insurance/reviews/support | Mix; several unavailable | [SERVER-OK]+[HARDCODED] |
| _DriverReviewsSheet | driver_profile_screen.dart:622 | Driver reviews | GET /drivers/{id}/reviews | [SERVER-OK] |
| DriverTaxProfileScreen | driver_tax_profile_screen.dart:9 | INN/taxpayer | GET/PUT /drivers/{id}/tax-profile | [SERVER-OK] |
| _submitProfile | driver_tax_profile_screen.dart:54 | Upsert tax | PUT /drivers/{id}/tax-profile | [SERVER-OK] |

## B9. Active-order restore (driver)
| Function | File:Line | What it does | Data source | Flag |
|---|---|---|---|---|
| _initializeDriver | new_driver_provider.dart:118 | Profile+active order+stats | GET /drivers/{id}, /orders/active, stats | [SERVER-OK] |
| getActiveOrder | via repository | Restore | GET /orders/active | [SERVER-OK] |
| driver_orders_history_screen.dart:12-55 | driverOrderHistoryProvider | MOCK list | HARDCODED | [HARDCODED] GAP |
| DriverOrdersHistoryScreen | driver_orders_history_screen.dart:59 | History UI | Hardcoded provider | [HARDCODED] GAP |

## B10. Driver realtime / matching feed
| Function | File:Line | What it does | Data source | Flag |
|---|---|---|---|---|
| availableOrdersProvider | available_orders_provider.dart:31 | WS stream | /ws/orders | [SERVER-OK] |
| Distance filter (5/10/all km) | available_orders_provider.dart:52-70 | Local filter | Geolocator local | [CLIENT-DECIDES] |
| Sort (price/distance/time) | available_orders_provider.dart:72-92 | Local sort | Local | [CLIENT-DECIDES] |
| connectAsDriver | driver_realtime_provider.dart:282 | WS driver connect | /ws/orders | [SERVER-OK] |
| DriverMapWidget | driver_map_widget.dart:7 | Map display | Props | [CLIENT-DECIDES] |

# PART C — "SERVER = SOURCE OF TRUTH" VIOLATIONS
All [CLIENT-DECIDES] + [HARDCODED] from Parts A+B, ranked by risk (money/order-state/pricing first).

## C1. CRITICAL (money / order state / pricing)
| # | Violation | File:Line | Why it's a risk | Server-authoritative version |
|---|---|---|---|---|
| C-01 | ETA shown to client is hardcoded strings ("5-10 мин", "едет к месту назначения") | tracking_screen.dart:238-247 | Client displays a wrong ETA; no real arrival estimate; trust/business impact | Server computes ETA from live driver route (/routing/orders/{id}/route duration) and streams it |
| C-02 | Client falls back to local price formula when server pricing is unavailable | order_flow_provider.dart:90-97, tariff.dart:16, price_calculator.dart:19 | Client can show/confirm a price the server never validated; mismatch at order creation | Always call POST /pricing/calculate; show "price unavailable" not a local guess |
| C-03 | Client price shown from local tariff multipliers on vehicle selection | vehicle_selection_screen.dart:532-574 (local path) | Multipliers drift from server; client displays wrong quote | Use GET /pricing/tariffs/{type} output only |
| C-04 | Default pricing constants baked in app (base 500₽, per km 25₽, min 800₽; vehicle multipliers 1.0/1.2/1.5/2.0) | core/constants: app_constants.dart:44-53 | If server tariffs change, app still quotes old prices | Delete local pricing constants; server /pricing/* is sole pricing source |
| C-05 | Distance used for price is computed on device (Haversine) | order_flow_provider.dart:478-493, price_calculator.dart:44 | Road distance ≠ straight line; client price estimate diverges from server quote | Use server /pricing/calculate which uses road routing distance |
| C-06 | Speed/distance assumptions for ETA/time (25-30 km/h, x1.2 multiplier) | location_service.dart:153, price_calculator.dart:77 | Fake ETAs shown to client | Server route duration from OSRM |
| C-07 | Order history (driver) is mock/hardcoded, not server | driver_orders_history_screen.dart:12-55 | Driver sees fake earnings/orders; no reconciliation | Wire to GET /orders (role driver) |
| C-08 | Driver moderation provider returns hardcoded "approved" | driver_moderation_provider.dart:71-85 | Driver may start work before docs verified; compliance risk | Use GET /drivers/{id}/verification-status |
| C-09 | Client polls order status every 2-3s instead of server push | order_flow_provider.dart:329, http_order_repository.dart:212, order_state_notifier.dart:213 | State can be stale; wasted bandwidth; no authoritative transition | Rely on WS order events; poll only as fallback |
| C-10 | Driver payment polling every 3s | new_driver_provider.dart:365-388 | Payment state decided client-side by polling | WS payment events / server push |

## C2. HIGH (order flow / dispatch decisions)
| # | Violation | File:Line | Why it's a risk | Server-authoritative version |
|---|---|---|---|---|
| C-11 | Driver filters available orders by distance locally (5/10/all km) | available_orders_provider.dart:52-70 | Driver may miss or hide server-offered jobs; inconsistent with matching | Server matches and sends only eligible offers |
| C-12 | Driver sorts offers locally (price/distance/time) | available_orders_provider.dart:72-92 | Offer priority not controlled by platform | Server dictates offer ordering / dispatch priority |
| C-13 | Client "blocked wheels" count is local state, sent implicitly | vehicle_selection_screen.dart:356-403 | Wheels count may not reach order payload correctly; affects pricing | Send as explicit order field; server stores it |
| C-14 | Client payment method chosen locally at vehicle screen | vehicle_selection_screen.dart:672-774 | Card-vs-cash decision not persisted/authoritative | Server stores payment_method on order; confirm via server |
| C-15 | Client comment is local until order submit | vehicle_selection_screen.dart:776-813 | Not validated/sanitized server-side before save | Server persists order.notes with validation |
| C-16 | Vehicle/tow types are hardcoded enums client-side | order_flow_provider.dart:169,178; vehicle_selection_screen.dart:17-27 | Adding a type requires app release; server can't push new types | GET /pricing/tariffs or /vehicle-types from server |
| C-17 | Client search timer and "no drivers" timeout decided locally | driver_search_screen.dart:265,367; app_constants.dart:28-33 (30 min) | Client may give up while server still searching | Server drives search lifecycle + timeout via WS |
| C-18 | Offer countdown driven by local timer from expiresAt | new_driver_home_screen.dart:163-211 | Clock skew; offer may expire differently | Server should reject accept-after-expiry; UI is cosmetic |
| C-19 | Client route refresh every 100m/30s decided locally | tracking_screen.dart:201-217 | Bandwidth; route decisions client-side | Server pushes route/duration updates |

## C3. MEDIUM (identity / profile)
| # | Violation | File:Line | Why it's a risk | Server-authoritative version |
|---|---|---|---|---|
| C-20 | User ID derived client-side as 'u'+phone digits | auth_provider.dart:612 | Client guesses identity; collides with server IDs | Use server-issued user id from /auth/otp/verify response |
| C-21 | Phone normalized to +7 client-side | auth_provider.dart:594 | Non-RU numbers mis-parse; mismatch with stored phone | Server canonicalizes phone |
| C-22 | Phone regex (11 digits starts with 7) hardcoded | auth_screen.dart:136 | Same as C-21 | Server validates phone |
| C-23 | Driver online duration computed locally | online_status_toggle.dart:122 | Display only; drift | Server could provide onlineSince |
| C-24 | Selfie/doc size rules hardcoded (700x700, 45KB) | driver_onboarding_provider.dart:175 | Server accepts more; client blocks valid uploads | Server validates on upload (10MB cap exists) |
| C-25 | Earnings DriverStats /100 TODO unaddressed | driver_earnings_provider.dart:85-95 | Potential wrong money display | Server returns consistent currency unit |

## C4. LOW (cosmetic / content)
| # | Violation | File:Line | Why it's a risk | Server-authoritative version |
|---|---|---|---|---|
| C-26 | Quick services grid hardcoded | client_home_screen.dart:508-534 | Can't be managed; "coming soon" | Server /services catalog |
| C-27 | SOS slider = "coming soon" | client_home_screen.dart:255-259 | Feature dead | Wire to real SOS flow |
| C-28 | Onboarding stats hardcoded ("<15 min", "4.9★", "6 200₽") | onboarding/role_selection_screen.dart:34-68 | Misleading marketing numbers | Server /platform-stats |
| C-29 | Rating label text hardcoded | driver_rating_screen.dart:410-425 | Cosmetic | Config |
| C-30 | History status colors hardcoded | client_history_screen.dart:341-364 | Cosmetic | Config |
| C-31 | Month names hardcoded | client_history_screen.dart:383-389 | Locale hardcoded | Intl/localization |
| C-32 | Profile "coming soon" tiles (notifications/emergency/support) | client_profile_screen.dart:96-115,203 | Dead UI | Wire real features |
| C-33 | App version/name hardcoded | app_constants.dart:2-3 | Cosmetic | Build config |
| C-34 | Moscow fallback coords hardcoded | app_constants.dart:55-56 | Wrong location shown when GPS fails | Server default region / "no location" state |
| C-35 | Base API URL hardcoded default | api_client_io.dart:10-11, app_config.dart | Release/build config risk | Env/remote config |
| C-36 | OSM user-agent "Avro mobile app" | openstreetmap_service.dart:12 | ToS | Config |

# PART D — OFFLINE BEHAVIOR (check, not rewrite)

## D1. Network layer
| Spot | File:Line | Behavior on no internet |
|---|---|---|
| HTTP client | core/network/api_client_io.dart:136-158 | Retries x3 (1s,2s backoff), then throws ApiClientException("Нет подключения к интернету", status 0). Does NOT crash. |
| HTTP client timeout | api_client_io.dart:18,107 | 30s timeout -> status 408 after retries. Hangs up to ~90s per call worst case. |
| Error surfacing | api_client_io.dart:182-220 | Every caller gets typed ApiClientException. Consumers must map to UI. |
| Auth retry | AuthRetryCoordinator (core/network/auth_retry_coordinator.dart:20) | 401 -> tries refresh -> logout on failure. OK. |

## D2. Key actions — no connectivity
| Action | What happens | Verdict |
|---|---|---|
| Create order | api_client_io.dart throws after retries; order_flow_provider.dart:255-307 catches? -> see GAP; if unhandled, spinner hangs up to ~90s then error | RISK of long hang; must show "no connection" cleanly |
| Price quote | /pricing/calculate fails -> localPriceFor fallback (order_flow_provider.dart:90) shows LOCAL price even offline | DEGRADES but WRONG (see C-02) |
| Tracking | WS drops -> realtime_location_service.dart catch + reconnect; location stream stops; map static | DEGRADES (stale), reconnect logic exists |
| Payment confirm | confirmPayment fails -> error surfaced via http_order_repository.dart:279; user retry | DEGRADES, needs retry UI |
| Cancel order | fails -> user cannot cancel while offline; no queue | BLOCKED (needs internet), acceptable |
| Driver online/offline | goOnline fails -> stays offline; goOffline POST fails -> may APPEAR offline but server thinks online | RISK: offline toggle silently fails (client shows offline, server still online -> driver won't get offers but is "online") |
| Review submit | createReview throws; caught at http_review_repository.dart:58, rethrows | DEGRADES with error message |
| SOS | offline_sos_screen.dart works fully OFFLINE (tel: + clipboard) | BEST CASE — designed for offline |
| Session restore | /auth/me fails -> offline_sos_screen.dart shown (main.dart:42 catch) | GRACEFUL — dedicated offline screen |
| Driver location send | WS location_update fails silently caught | SILENT degradation (location stale) |
| Search WS create | driver_search_screen.dart:35-78, if WS connect fails -> no clean state? | RISK of stuck "searching" state |

## D3. Crash vs graceful summary
- CRASH/HANG RISK: order creation when server unreachable (long retry window, no early "no connection" banner at flow start).
- STUCK-STATE RISK: driver WS create/search; online/offline toggle failure; "searching" with no drivers event.
- GRACEFUL: auth session restore (offline_sos_screen), SOS, read-only history when cached.
- NO connectivity detection: no connectivity_plus usage; only rely on per-request exceptions. No global "offline banner" except WS status banner (client_app_shell.dart:31-51).

# PART E — GAPS / UNFINISHED
| # | Gap | File:Line | Status |
|---|---|---|---|
| E-01 | Acquiring provider (Точка/Cyclops) payment flow stubbed | features/order/screens/payment_confirmation_screen.dart:201 | TODO, YooKassa in use |
| E-02 | Driver order history = mock data | driver_orders_history_screen.dart:12-55 | [HARDCODED] must wire GET /orders |
| E-03 | Driver moderation provider = fake approved | driver_moderation_provider.dart:71-85 | [HARDCODED] must wire verification-status |
| E-04 | ModerationWaitingScreen static | moderation_waiting_screen.dart:5-116 | No live status polling |
| E-05 | Review screen redirect TODO | main.dart:29,110 | "remove when review screen confirmed" |
| E-06 | InMemory storage TODO | core/storage/key_value_storage.dart:15 | Replace with persistent storage |
| E-07 | Crash analytics TODO | core/error/global_error_handler.dart:31,50 | Not wired |
| E-08 | UTF-8 geocoding TODO | client_home_screen.dart:302 | Encoding workaround |
| E-09 | Earnings /100 TODO | driver_earnings_provider.dart:85-95 | Currency unit ambiguity |
| E-10 | Message driver button = SMS fallback | driver_info_screen.dart:29-32 | Chat not implemented |
| E-11 | Legacy driver screens remain (tow_truck_selection_screen, active_order_card, driver_status_provider) | tow_truck_selection_screen.dart, active_order_card.dart:10, driver_status_provider.dart:150 | Duplicate/legacy paths vs new_driver_* |
| E-12 | Notification/emergency/support/profile tiles "coming soon" | client_profile_screen.dart:96-115,203 | Dead UI |
| E-13 | Quick services + SOS slider "coming soon" | client_home_screen.dart:255,508 | Dead UI |
| E-14 | ServiceDetailScreen "call mechanic" = snackbar | service_detail_screen.dart:232-257 | Not wired |
| E-15 | Promocode: server only supports "EVIK2025"=10% | backend payment_handler.go:1077 | Single hardcoded promo |
| E-16 | `test_main.dart` / `main.dart` alternate entry | test_main.dart:175 | Test entry shipping |

## README/arch drift
- README.md:123-131 documents state machine created->searching->accepted->arrived->in_progress->completed; actual backend adds awaiting_payment + finalize. Frontend statuses (idle/searching/accepted/arrived/inProgress/completed/cancelled) need reconciliation with server (awaiting_payment, in_progress naming).
