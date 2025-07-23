# BLE_Scanner

BLE_Scanner 是一個支援掃描與廣播特定封包，並且支援 MQTT 通訊，將資料儲存到雲端的 iOS App。

## 支援環境

- Xcode 16
- iOS 15.6 或以上版本

## 使用說明

1. 下載本專案後，**專案中可能會看到紅色的 `MQTTCredentials.plist` 檔案**（找不到的情況）。
   - 請在該檔案上點選 **右鍵 → Delete → Remove Reference**，將其移除參考。

2. 找到並打開 `MQTTCredentials_example.plist`，填入以下欄位：
   
   | Key       | 說明                               |
   |-----------|-----------------------------------|
   | `host`    | MQTT broker 的 IP 或網址           |
   | `port`    | MQTT broker 的連接埠（預設為 `1883`） |
   | `username`| MQTT broker 登入帳號               |
   | `password`| MQTT broker 登入密碼               |

3. 將修改後的檔案**另存為 `MQTTCredentials.plist`**，放在原本的位置（通常在 `BLE_Scanner/BLE_Scanner/` 資料夾內）。

4. 完成設定後，就可以使用 Xcode 執行專案，將 App 安裝到 iPhone 或 iPad 裝置中。

## 注意事項

- **請勿將 `MQTTCredentials.plist` 上傳到 GitHub**，以免洩露個人敏感資訊。
- 已在 `.gitignore` 中忽略該檔案。
