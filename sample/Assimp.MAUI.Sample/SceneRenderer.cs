using System.Reflection;
using System.Runtime.InteropServices;
using Assimp.Maui;

namespace Assimp.MAUI.Sample;

internal sealed class SceneRenderer : IDrawable
{
    private readonly List<Triangle> _triangles = [];
    private float _rotationX = -0.35f;
    private float _rotationY = 0.55f;
    private float _scale = 1f;

    public int MeshCount { get; private set; }
    public int VertexCount { get; private set; }
    public int FaceCount { get; private set; }

    public void SetScene(Scene? scene)
    {
        _triangles.Clear();
        MeshCount = 0;
        VertexCount = 0;
        FaceCount = 0;

        if (scene is null || !scene.HasMeshes())
            return;

        MeshCount = checked((int)scene.NumMeshes);

        try
        {
            var meshes = GetHandle(scene.Meshes);
            var meshType = typeof(Mesh);
            var constructor = meshType.GetConstructor(
                BindingFlags.Instance | BindingFlags.NonPublic,
                binder: null,
                [typeof(IntPtr), typeof(bool)],
                modifiers: null);

            if (constructor is null)
                throw new MissingMethodException(meshType.FullName, ".ctor(IntPtr, Boolean)");

            for (var meshIndex = 0; meshIndex < MeshCount; meshIndex++)
            {
                var meshPointer = Marshal.ReadIntPtr(meshes, meshIndex * IntPtr.Size);
                if (meshPointer == IntPtr.Zero)
                    continue;

                using var mesh = (Mesh)constructor.Invoke([meshPointer, false]);
                if (!mesh.HasPositions() || !mesh.HasFaces())
                    continue;

                VertexCount += checked((int)mesh.NumVertices);
                FaceCount += checked((int)mesh.NumFaces);
                ReadMesh(mesh);
            }
        }
        catch
        {
            _triangles.Clear();
            throw;
        }

        Normalize();
    }

    public void ResetCamera()
    {
        _rotationX = -0.35f;
        _rotationY = 0.55f;
        _scale = 1f;
    }

    public void Rotate(float deltaX, float deltaY)
    {
        _rotationY += deltaX * 0.01f;
        _rotationX += deltaY * 0.01f;
    }

    public void Zoom(float delta)
    {
        _scale = Math.Clamp(_scale * (1f + delta), 0.1f, 10f);
    }

    public void Draw(ICanvas canvas, RectF dirtyRect)
    {
        canvas.FillColor = Colors.Black;
        canvas.FillRectangle(dirtyRect);

        if (_triangles.Count == 0)
        {
            canvas.FontColor = Colors.White;
            canvas.FontSize = 16;
            canvas.DrawString("Load a supported 3D asset to preview its scene.",
                dirtyRect.Center.X, dirtyRect.Center.Y,
                HorizontalAlignment.Center);
            return;
        }

        var projected = new List<ProjectedTriangle>(_triangles.Count);

        foreach (var triangle in _triangles)
        {
            var a = Project(triangle.A, dirtyRect);
            var b = Project(triangle.B, dirtyRect);
            var c = Project(triangle.C, dirtyRect);

            projected.Add(new ProjectedTriangle(a, b, c, (a.Z + b.Z + c.Z) / 3f));
        }

        foreach (var triangle in projected.OrderBy(t => t.Depth))
        {
            var path = new PathF();
            path.MoveTo(triangle.A.X, triangle.A.Y);
            path.LineTo(triangle.B.X, triangle.B.Y);
            path.LineTo(triangle.C.X, triangle.C.Y);
            path.Close();

            canvas.FillColor = new Color(0.28f, 0.55f, 0.95f, 0.72f);
            canvas.FillPath(path);

            canvas.StrokeColor = new Color(0.8f, 0.9f, 1f, 0.55f);
            canvas.StrokeSize = 0.5f;
            canvas.DrawPath(path);
        }
    }

    private void ReadMesh(Mesh mesh)
    {
        var vertices = GetHandle(mesh.Vertices);
        var faces = GetHandle(mesh.Faces);

        var vertexCount = checked((int)mesh.NumVertices);
        var verticesData = new Point3D[vertexCount];

        for (var i = 0; i < vertexCount; i++)
        {
            var address = IntPtr.Add(vertices, i * 12);
            var values = new float[3];
            Marshal.Copy(address, values, 0, 3);
            verticesData[i] = new Point3D(values[0], values[1], values[2]);
        }

        var faceStride = IntPtr.Size == 8 ? 16 : 8;

        for (var faceIndex = 0; faceIndex < mesh.NumFaces; faceIndex++)
        {
            var faceAddress = IntPtr.Add(faces, checked((int)faceIndex) * faceStride);
            var indexCount = checked((int)(uint)Marshal.ReadInt32(faceAddress));

            if (indexCount < 3)
                continue;

            var indicesAddress = Marshal.ReadIntPtr(
                IntPtr.Add(faceAddress, IntPtr.Size == 8 ? 8 : 4));

            if (indicesAddress == IntPtr.Zero)
                continue;

            var first = ReadVertex(verticesData, indicesAddress, 0);
            for (var i = 1; i < indexCount - 1; i++)
            {
                var second = ReadVertex(verticesData, indicesAddress, i);
                var third = ReadVertex(verticesData, indicesAddress, i + 1);
                _triangles.Add(new Triangle(first, second, third));
            }
        }
    }

    private static Point3D ReadVertex(Point3D[] vertices, IntPtr indices, int index)
    {
        var vertexIndex = Marshal.ReadInt32(IntPtr.Add(indices, index * sizeof(uint)));
        return vertexIndex >= 0 && vertexIndex < vertices.Length
            ? vertices[vertexIndex]
            : default;
    }

    private void Normalize()
    {
        if (_triangles.Count == 0)
            return;

        var points = _triangles.SelectMany(t => new[] { t.A, t.B, t.C }).ToArray();
        var minX = points.Min(p => p.X);
        var maxX = points.Max(p => p.X);
        var minY = points.Min(p => p.Y);
        var maxY = points.Max(p => p.Y);
        var minZ = points.Min(p => p.Z);
        var maxZ = points.Max(p => p.Z);

        var center = new Point3D(
            (minX + maxX) / 2f,
            (minY + maxY) / 2f,
            (minZ + maxZ) / 2f);

        var size = Math.Max(maxX - minX, Math.Max(maxY - minY, maxZ - minZ));
        if (size <= 0)
            size = 1;

        var factor = 2f / size;

        for (var i = 0; i < _triangles.Count; i++)
        {
            var t = _triangles[i];
            _triangles[i] = new Triangle(
                Center(t.A, center, factor),
                Center(t.B, center, factor),
                Center(t.C, center, factor));
        }
    }

    private Point3D Project(Point3D point, RectF bounds)
    {
        var cosY = MathF.Cos(_rotationY);
        var sinY = MathF.Sin(_rotationY);
        var cosX = MathF.Cos(_rotationX);
        var sinX = MathF.Sin(_rotationX);

        var x = point.X * cosY - point.Z * sinY;
        var z = point.X * sinY + point.Z * cosY;
        var y = point.Y * cosX - z * sinX;
        z = point.Y * sinX + z * cosX;

        var perspective = 2.8f / (3.4f - z);
        var size = MathF.Min(bounds.Width, bounds.Height) * 0.4f * _scale;

        return new Point3D(
            bounds.Center.X + x * perspective * size,
            bounds.Center.Y - y * perspective * size,
            z);
    }

    private static Point3D Center(Point3D point, Point3D center, float factor) =>
        new((point.X - center.X) * factor, (point.Y - center.Y) * factor, (point.Z - center.Z) * factor);

    private static IntPtr GetHandle(object value)
    {
        var field = value.GetType().GetField("swigCPtr",
            BindingFlags.Instance | BindingFlags.NonPublic)
            ?? throw new MissingFieldException(value.GetType().FullName, "swigCPtr");

        var handle = (HandleRef)field.GetValue(value)!;
        return handle.Handle;
    }

    private readonly record struct Point3D(float X, float Y, float Z);
    private readonly record struct Triangle(Point3D A, Point3D B, Point3D C);
    private readonly record struct ProjectedTriangle(Point3D A, Point3D B, Point3D C, float Depth);
}
