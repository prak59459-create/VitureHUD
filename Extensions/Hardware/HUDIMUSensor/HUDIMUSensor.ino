// HUD Navigator 用の頭の向きセンサー（自作・参考用）
// 対応ボード例：M5StickC Plus2 / M5StickC Plus / M5Atom Matrix（IMU 内蔵の ESP32）
// 必要なライブラリ：M5Unified（Arduino IDE のライブラリマネージャーから）
//
// グラスのつるに付けて電源を入れると「HUD-IMU」という名前で Bluetooth に現れます。
// アプリの 設定 → 頭の動き → 「Bluetooth の動きセンサー」→「センサーを探す」で接続します。
//
// 送るデータ（約 50 回/秒）：yaw・pitch・roll（度）と加速度 x・y・z（G）を float32（リトルエンディアン）で 24 バイト。
// 向き：右を向く＝yaw がプラス、上を向く＝pitch がプラス、右に傾ける＝roll がプラス。
// 付け方で向きが違う場合は、アプリ側の「反転」「入れ替え」で合わせてください。
//
// ※ この スケッチ は CI ではビルドしていません（参考実装）。

#include <M5Unified.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLE2902.h>

static const char* SERVICE_UUID = "4855444E-4156-4900-8000-494D55000000";
static const char* POSE_UUID    = "4855444E-4156-4900-8000-494D55000001";

BLECharacteristic* poseChar = nullptr;
bool connected = false;
float yaw = 0, pitch = 0, roll = 0;
uint32_t lastMicros = 0;

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer*) override { connected = true; }
  void onDisconnect(BLEServer* s) override { connected = false; s->getAdvertising()->start(); }
};

void setup() {
  auto cfg = M5.config();
  M5.begin(cfg);
  M5.Imu.begin();
  BLEDevice::init("HUD-IMU");
  BLEServer* server = BLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());
  BLEService* service = server->createService(SERVICE_UUID);
  poseChar = service->createCharacteristic(POSE_UUID, BLECharacteristic::PROPERTY_NOTIFY | BLECharacteristic::PROPERTY_READ);
  poseChar->addDescriptor(new BLE2902());
  service->start();
  BLEAdvertising* adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(SERVICE_UUID);
  adv->start();
  lastMicros = micros();
}

void loop() {
  M5.update();
  M5.Imu.update();
  auto d = M5.Imu.getImuData();
  uint32_t now = micros();
  float dt = (now - lastMicros) / 1e6f;
  lastMicros = now;

  // 相補フィルター：傾き（pitch・roll）は加速度とジャイロ、向き（yaw）はジャイロの積分（時間とともにずれるのでアプリで「正面にする」）
  float accPitch = atan2f(d.accel.y, sqrtf(d.accel.x * d.accel.x + d.accel.z * d.accel.z)) * 180.0f / PI;
  float accRoll  = atan2f(-d.accel.x, d.accel.z) * 180.0f / PI;
  pitch = 0.98f * (pitch + d.gyro.x * dt) + 0.02f * accPitch;
  roll  = 0.98f * (roll  + d.gyro.y * dt) + 0.02f * accRoll;
  yaw  -= d.gyro.z * dt;
  if (yaw > 180) yaw -= 360;
  if (yaw < -180) yaw += 360;

  if (connected && poseChar) {
    float data[6] = { yaw, pitch, roll, d.accel.x, d.accel.y, d.accel.z };
    poseChar->setValue((uint8_t*)data, sizeof(data));
    poseChar->notify();
  }
  delay(20);
}
