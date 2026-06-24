using NAudio.Wave;
using TimeoutEngine.Win32;

namespace TimeoutShell.Adapters;

// 粉噪音播放 · NAudio WasapiOut 循环播放 PinkNoiseGenerator 产出的 8s buffer。
// 对齐 macOS AmbientSoundPlayer：预生成 buffer 无缝循环 + 音量 0.4 + 启动失败降级不崩。
// WASAPI 共享模式可与 QQ 音乐混音（对齐 macOS CoreAudio 自动混音）。
public sealed class WasapiAmbientPlayer : IDisposable
{
    private const float Volume = 0.4f;
    private readonly float[] _samples;
    private WasapiOut? _player;
    private LoopSampleProvider? _source;
    public bool IsPlaying { get; private set; }

    public WasapiAmbientPlayer(PinkNoiseGenerator generator) => _samples = generator.Generate(8);

    public void Start()
    {
        if (IsPlaying) return;
        try
        {
            _source = new LoopSampleProvider(_samples);
            var vol = new VolumeSampleProvider(_source) { Volume = Volume };
            _player = new WasapiOut();
            _player.Init(vol.ToWaveProvider());
            _player.Play();
            IsPlaying = true;
            Console.WriteLine("[Timeout][ambient] 粉噪音已启动");
        }
        catch (Exception ex)
        {
            // CI 无音频设备 / headless：降级静默（对齐 macOS do/catch 不崩语义）
            Console.WriteLine($"[Timeout][ambient] WASAPI 启动失败（降级静默）：{ex.Message}");
        }
    }

    public void Stop()
    {
        if (!IsPlaying) return;
        try { _player?.Stop(); } catch { }
        try { _player?.Dispose(); } catch { }
        _player = null;
        _source = null;
        IsPlaying = false;
        Console.WriteLine("[Timeout][ambient] 粉噪音已停止");
    }

    public void Dispose() => Stop();

    /// <summary>循环读取预生成 buffer 的 ISampleProvider（IEEE float 单声道）。</summary>
    internal sealed class LoopSampleProvider : ISampleProvider
    {
        private readonly float[] _data;
        private int _pos;
        public WaveFormat WaveFormat { get; }

        public LoopSampleProvider(float[] data, int sampleRate = 44100)
        {
            _data = data;
            WaveFormat = WaveFormat.CreateIeeeFloatWaveFormat(sampleRate, 1);
        }

        public int Read(float[] buffer, int offset, int count)
        {
            for (int i = 0; i < count; i++)
            {
                buffer[offset + i] = _data[_pos];
                _pos = (_pos + 1) % _data.Length;
            }
            return count;
        }
    }
}
