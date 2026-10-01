# Classic Mac Alarm Clock — desk-accessory tribute (Free Pascal)
#
# macOS:   make
# Linux:   sudo apt install fpc libgtk2.0-dev   &&  make linux
# Windows: from a native FPC install:            make windows

FPC      ?= fpc
SRC      := src
BUILD    := build
APP      := $(BUILD)/AlarmClock.app
UNITS    := -Fu$(SRC) -FU$(BUILD) -FE$(BUILD)
FLAGS    := -Mobjfpc -Scgi -O2 -Xs

.PHONY: all app run linux windows test snap clean

all: app

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/AlarmClock: $(BUILD) $(SRC)/*.pas
	$(FPC) $(FLAGS) $(UNITS) -o$(BUILD)/AlarmClock $(SRC)/alarm.pas

$(BUILD)/alarmtest: $(BUILD) $(SRC)/ualarmmodel.pas $(SRC)/ualarmrender.pas $(SRC)/ualarmapp.pas $(SRC)/alarmtest.pas
	$(FPC) $(FLAGS) $(UNITS) -o$(BUILD)/alarmtest $(SRC)/alarmtest.pas

$(BUILD)/alarmsnap: $(BUILD) $(SRC)/ualarmmodel.pas $(SRC)/ualarmrender.pas $(SRC)/ualarmapp.pas $(SRC)/alarmsnap.pas
	$(FPC) $(FLAGS) $(UNITS) -o$(BUILD)/alarmsnap $(SRC)/alarmsnap.pas

app: $(BUILD)/AlarmClock
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BUILD)/AlarmClock $(APP)/Contents/MacOS/AlarmClock
	cp bundle/Info.plist $(APP)/Contents/Info.plist

run: app
	open $(APP)

linux: $(BUILD)
	$(FPC) $(FLAGS) $(UNITS) -o$(BUILD)/alarmclock $(SRC)/alarm.pas

windows: $(BUILD)
	$(FPC) $(FLAGS) $(UNITS) -o$(BUILD)/AlarmClock.exe $(SRC)/alarm.pas

test: $(BUILD)/alarmtest
	$(BUILD)/alarmtest

snap: $(BUILD)/alarmsnap
	$(BUILD)/alarmsnap $(BUILD)

clean:
	rm -rf $(BUILD)
