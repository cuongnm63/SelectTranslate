APP_NAME := SelectTranslate
# Bundle .app nằm ngoài ~/Desktop: iCloud (File Provider) gắn com.apple.FinderInfo lên .app
# trong thư mục đồng bộ → codesign báo "detritus not allowed".
APP_DIR  ?= $(HOME)/Library/Caches/$(APP_NAME)
APP      := $(APP_DIR)/$(APP_NAME).app
export APP_DIR
BUNDLE_ID := com.cuongnguyen.SelectTranslate

.PHONY: build app run install dmg reset-ax clean

build:            ## Chỉ compile (kiểm tra lỗi)
	swift build

app:              ## Build + đóng gói .app
	./scripts/build-app.sh

run: app          ## Build rồi mở app
	-pkill -x $(APP_NAME)
	open $(APP)

install: app      ## Copy vào /Applications
	-pkill -x $(APP_NAME)
	rm -rf /Applications/$(APP_NAME).app
	cp -R $(APP) /Applications/
	open /Applications/$(APP_NAME).app

dmg:              ## Đóng gói DMG để chia sẻ (xem README)
	./scripts/release.sh

reset-ax:         ## Xoá quyền Accessibility cũ (khi rebuild ad-hoc bị mất quyền)
	tccutil reset Accessibility $(BUNDLE_ID)

clean:
	rm -rf .build build "$(APP_DIR)"
