package http

import (
	"errors"
	"net/http"

	accuc "evik/backend/internal/usecase/account"
)

type AccountHandler struct {
	deleteUC *accuc.UseCase
}

func NewAccountHandler(deleteUC *accuc.UseCase) *AccountHandler {
	return &AccountHandler{deleteUC: deleteUC}
}

// @Summary      Delete my account
// @Description  Irreversibly deletes the caller's own account: PII is
//               anonymized, all sessions/tokens are revoked and login is
//               disabled. Financial/order records are retained anonymized for
//               tax/legal compliance. Refused (409) while the account has an
//               active order or an outstanding driver's wallet balance.
// @Tags         account
// @Produce      json
// @Security     BearerAuth
// @Success      200  {object}  map[string]any  "account deleted"
// @Failure      401  {object}  ErrorResponse  "unauthorized"
// @Failure      409  {object}  ErrorResponse  "active order or outstanding balance"
// @Router       /account [delete]
func (h *AccountHandler) Delete(w http.ResponseWriter, r *http.Request) {
	userID, err := userIDFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	role, err := roleFromContext(r.Context())
	if err != nil {
		writeAuthError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	if err := h.deleteUC.Execute(r.Context(), userID, role); err != nil {
		switch {
		case errors.Is(err, accuc.ErrActiveOrder):
			writeJSON(w, http.StatusConflict, map[string]string{"error": "завершите текущий заказ, чтобы удалить аккаунт"})
		case errors.Is(err, accuc.ErrOutstandingDriverBalance):
			writeJSON(w, http.StatusConflict, map[string]string{"error": "выведите или погасите баланс, чтобы удалить аккаунт"})
		case errors.Is(err, accuc.ErrAccountNotFound):
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "account not found"})
		default:
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
		}
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}