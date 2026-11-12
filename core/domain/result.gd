## 操作の成否を表す基底の値（architecture.md 3 節 core/domain）。
##
## 目的: UseCase と Repository が「成功か、失敗か（理由つき）」を例外なしで返すための型。
## 使い方:
##   1. 成否だけの UseCase は Result をそのまま返す: Result.success() / Result.failure(error)
##   2. 値も返す UseCase は、UseCase ごとの結果型（*_result.gd）がこのクラスを継承し、
##      値のフィールドを足す（結果型は共用しない。architecture.md 軽量化の指針 2）
##   3. 呼び出し側は ok を見て分岐し、失敗なら error（AppError）の kind で表示と動線を決める
## 失敗時の扱い: 失敗は ok = false と error で表す。error は失敗のとき必ず入れる（null にしない）。
class_name Result
extends RefCounted

## 成功なら true
var ok: bool = true
## 失敗の理由。成功のときは null
var error: AppError = null


## 継承先（*_result.gd）が super(ok, error) で呼べるよう、引数を持つ。
func _init(p_ok: bool = true, p_error: AppError = null) -> void:
	ok = p_ok
	error = p_error


## 成功を返す。
static func success() -> Result:
	return Result.new(true, null)


## 失敗を返す。p_error は null にしない（呼び出し側が kind で分岐するため）。
static func failure(p_error: AppError) -> Result:
	return Result.new(false, p_error)
