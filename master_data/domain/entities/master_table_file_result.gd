## MasterDataRemoteRepository.download_table() の結果。成功ならファイルの中身（SQLite のバイト列）を持つ。
class_name MasterTableFileResult
extends Result

var bytes: PackedByteArray = PackedByteArray()


func _init(p_bytes: PackedByteArray = PackedByteArray(), p_error: AppError = null) -> void:
	super(p_error == null, p_error)
	bytes = p_bytes
