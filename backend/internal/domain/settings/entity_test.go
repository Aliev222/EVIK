package settings

import (
	"testing"
)

func TestGetIntFloat64(t *testing.T) {
	list := []Setting{
		{Key: "test_key", Value: float64(42)},
	}
	got := GetInt(list, "test_key", 0)
	if got != 42 {
		t.Errorf("GetInt = %d, want 42", got)
	}
}

func TestGetIntStringParseInt(t *testing.T) {
	list := []Setting{
		{Key: "test_key", Value: "30"},
	}
	got := GetInt(list, "test_key", 0)
	if got != 30 {
		t.Errorf("GetInt = %d, want 30", got)
	}
}

func TestGetIntStringParseFloat(t *testing.T) {
	list := []Setting{
		{Key: "test_key", Value: "15.00"},
	}
	got := GetInt(list, "test_key", 0)
	if got != 15 {
		t.Errorf("GetInt = %d, want 15", got)
	}
}

func TestGetIntKeyMissing(t *testing.T) {
	list := []Setting{
		{Key: "other_key", Value: float64(99)},
	}
	got := GetInt(list, "test_key", 10)
	if got != 10 {
		t.Errorf("GetInt = %d, want fallback 10", got)
	}
}

func TestGetIntInvalidValue(t *testing.T) {
	list := []Setting{
		{Key: "test_key", Value: "abc"},
	}
	got := GetInt(list, "test_key", 7)
	if got != 7 {
		t.Errorf("GetInt = %d, want fallback 7", got)
	}
}

func TestGetIntBoolValue(t *testing.T) {
	list := []Setting{
		{Key: "test_key", Value: true},
	}
	got := GetInt(list, "test_key", 5)
	if got != 5 {
		t.Errorf("GetInt = %d, want fallback 5", got)
	}
}

func TestGetIntEmptyList(t *testing.T) {
	got := GetInt(nil, "test_key", 99)
	if got != 99 {
		t.Errorf("GetInt = %d, want fallback 99", got)
	}
}

func TestGetIntTruncatesFloat(t *testing.T) {
	list := []Setting{
		{Key: "test_key", Value: float64(20.75)},
	}
	got := GetInt(list, "test_key", 0)
	if got != 20 {
		t.Errorf("GetInt = %d, want 20 (truncated)", got)
	}
}
