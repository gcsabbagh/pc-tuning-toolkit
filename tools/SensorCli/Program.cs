using System.Reflection;
using System.Runtime.Intrinsics;
using System.Runtime.Intrinsics.X86;
using System.Runtime.Loader;

string[] probeDirs = new[]
{
    Path.Combine(AppContext.BaseDirectory, "lhm"),
    Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "bin", "lhm")),
    @"C:\Program Files (x86)\FanControl",
    @"C:\Program Files\FanControl"
};

string? lhmDir = probeDirs.FirstOrDefault(d => File.Exists(Path.Combine(d, "LibreHardwareMonitorLib.dll")));
if (lhmDir == null)
{
    Console.Error.WriteLine("ERROR: LibreHardwareMonitorLib.dll not found. Run .\\scripts\\Bootstrap-Tools.ps1 or install FanControl.");
    Environment.Exit(1);
}

AssemblyLoadContext.Default.Resolving += (context, name) =>
{
    string candidate = Path.Combine(lhmDir, name.Name + ".dll");
    if (File.Exists(candidate))
        return context.LoadFromAssemblyPath(candidate);
    return null;
};

var asm = AssemblyLoadContext.Default.LoadFromAssemblyPath(Path.Combine(lhmDir, "LibreHardwareMonitorLib.dll"));
var compType = asm.GetType("LibreHardwareMonitor.Hardware.Computer")!;
var isensorType = asm.GetType("LibreHardwareMonitor.Hardware.ISensor")!;
var valProp = isensorType.GetProperty("Value")!;
var nameProp = isensorType.GetProperty("Name")!;
var typeProp = isensorType.GetProperty("SensorType")!;

dynamic comp = Activator.CreateInstance(compType)!;
comp.IsCpuEnabled = true;
comp.IsMotherboardEnabled = true;
comp.IsMemoryEnabled = true;
comp.IsGpuEnabled = args.Contains("--include-gpu");
comp.Open();

bool runStress = args.Contains("--stress");
bool includeTimings = args.Contains("--timings");
int stressSecPerPhase = 9;
int idxStress = Array.IndexOf(args, "--stress");
if (idxStress >= 0 && idxStress + 1 < args.Length && int.TryParse(args[idxStress + 1], out int customSec))
{
    stressSecPerPhase = Math.Max(3, customSec / 2);
}

using var cts = new CancellationTokenSource();
int stressMode = 0; // 0 = idle, 1 = scalar, 2 = AVX2+FMA

var workers = new List<Task>();
if (runStress)
{
    int threads = Environment.ProcessorCount;
    for (int t = 0; t < threads; t++)
    {
        workers.Add(Task.Run(() =>
        {
            double s = 1.0000001;
            var v1 = Vector256.Create(1.0000001, 1.0000002, 1.0000003, 1.0000004);
            var v2 = Vector256.Create(0.9999999, 0.9999998, 0.9999997, 0.9999996);
            var acc = Vector256.Create(1.0, 2.0, 3.0, 4.0);
            while (!cts.Token.IsCancellationRequested)
            {
                int mode = Volatile.Read(ref stressMode);
                if (mode == 0)
                {
                    Thread.Sleep(50);
                }
                else if (mode == 1)
                {
                    for (int i = 0; i < 2_000_000; i++)
                    {
                        s = Math.Sqrt(s * 1.0000001 + 0.0000001);
                    }
                }
                else
                {
                    for (int i = 0; i < 5_000_000; i++)
                    {
                        if (Fma.IsSupported && Avx.IsSupported)
                        {
                            acc = Fma.MultiplyAdd(acc, v1, v2);
                            acc = Avx.Sqrt(acc);
                        }
                        else
                        {
                            s = Math.Sqrt(s * 1.0000001 + 0.0000001);
                        }
                    }
                }
            }
            GC.KeepAlive(s);
            GC.KeepAlive(acc);
        }));
    }
}

void PrintSnapshot(string label)
{
    Console.WriteLine($"\n================ {label} ({DateTime.Now:HH:mm:ss}) ================");
    foreach (dynamic hw in comp.Hardware)
    {
        hw.Update();
        string hwType = hw.HardwareType.ToString();
        string rawHwName = (string)hw.Name.ToString();
        string hwName = new string(rawHwName.Split('\0')[0].Where(c => c >= 32 && c <= 126).ToArray()).Trim();
        if (hwType == "Memory" && (hwName.Contains("Virtual") || hwName.Contains("Total Memory")))
            continue;

        Console.WriteLine($"=== {hwName} ({hwType}) ===");
        foreach (dynamic sub in hw.SubHardware)
        {
            sub.Update();
            Console.WriteLine($"  [{sub.Name}]");
            foreach (object sensor in sub.Sensors)
            {
                object? raw = valProp.GetValue(sensor);
                string sType = typeProp.GetValue(sensor)!.ToString()!;
                string sName = nameProp.GetValue(sensor)!.ToString()!;
                if (raw is float v && (sType == "Temperature" || sType == "Fan" || sName.Contains("Vcore") || sName.Contains("VSOC") || sName.Contains("Voltage #")))
                    Console.WriteLine($"    {sType,-12} | {sName,-35} | {v,10:F2}");
            }
        }
        foreach (object sensor in hw.Sensors)
        {
            object? raw = valProp.GetValue(sensor);
            string sType = typeProp.GetValue(sensor)!.ToString()!;
            string sName = nameProp.GetValue(sensor)!.ToString()!;
            if (!includeTimings && sType == "Timing") continue;
            if (raw is float v && !sName.Contains("Distance to TjMax") && !sName.Contains("Limit") && !sName.Contains("Resolution"))
                Console.WriteLine($"  {sType,-12} | {sName,-35} | {v,10:F2}");
        }
    }
}

if (runStress)
{
    PrintSnapshot("IDLE BASELINE");
    int steps = Math.Max(1, stressSecPerPhase / 3);

    Volatile.Write(ref stressMode, 1);
    for (int i = 1; i <= steps; i++)
    {
        Thread.Sleep(3000);
        PrintSnapshot($"SCALAR ALL-CORE LOAD ({i * 3}s)");
    }

    Volatile.Write(ref stressMode, 2);
    for (int i = 1; i <= steps + 1; i++)
    {
        Thread.Sleep(3000);
        PrintSnapshot($"AVX2 + FMA ALL-CORE LOAD ({i * 3}s)");
    }

    cts.Cancel();
    Task.WaitAll(workers.ToArray(), 2000);
    Thread.Sleep(2000);
    PrintSnapshot("COOLDOWN (2s AFTER STOP)");
}
else
{
    int samples = args.Length > 0 && int.TryParse(args[0], out int s) ? s : 1;
    int delayMs = args.Length > 1 && int.TryParse(args[1], out int d) ? d : 1000;
    for (int i = 0; i < samples; i++)
    {
        if (i > 0) Thread.Sleep(delayMs);
        PrintSnapshot($"SAMPLE {i + 1}/{samples}");
    }
}

comp.Close();
