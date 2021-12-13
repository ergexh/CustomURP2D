using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using System;
using Unity.Collections;
using System.Linq;
using UnityEngine.Experimental.Rendering.Universal.LibTessDotNet;


namespace UnityEngine.Experimental.Rendering.Universal
{
    internal class ShadowUtility
    {
        internal struct Edge : IComparable<Edge>
        {
            public int vertexIndex0;
            public int vertexIndex1;
            public Vector4 tangent;
            private bool compareReversed; // This is done so that edge AB can equal edge BA

            public void AssignVertexIndices(int vi0, int vi1)
            {
                vertexIndex0 = vi0;
                vertexIndex1 = vi1;
                compareReversed = vi0 > vi1;
            }

            public int Compare(Edge a, Edge b)
            {
                int adjustedVertexIndex0A = a.compareReversed ? a.vertexIndex1 : a.vertexIndex0;
                int adjustedVertexIndex1A = a.compareReversed ? a.vertexIndex0 : a.vertexIndex1;
                int adjustedVertexIndex0B = b.compareReversed ? b.vertexIndex1 : b.vertexIndex0;
                int adjustedVertexIndex1B = b.compareReversed ? b.vertexIndex0 : b.vertexIndex1;

                // Sort first by VI0 then by VI1
                int deltaVI0 = adjustedVertexIndex0A - adjustedVertexIndex0B;
                int deltaVI1 = adjustedVertexIndex1A - adjustedVertexIndex1B;

                if (deltaVI0 == 0)
                    return deltaVI1;
                else
                    return deltaVI0;
            }

            public int CompareTo(Edge edgeToCompare)
            {
                return Compare(this, edgeToCompare);
            }
        }

        static Edge CreateEdge(int triangleIndexA, int triangleIndexB, List<Vector3> vertices, List<int> triangles)
        {
            Edge retEdge = new Edge();

            retEdge.AssignVertexIndices(triangles[triangleIndexA], triangles[triangleIndexB]);
            
            Vector3 vertex0 = vertices[retEdge.vertexIndex0];
            vertex0.z = 0;
            Vector3 vertex1 = vertices[retEdge.vertexIndex1];
            vertex1.z = 0;

            Vector3 edgeDir = Vector3.Normalize(vertex1 - vertex0);
            retEdge.tangent = Vector3.Cross(-Vector3.forward, edgeDir);

            return retEdge;
        }

        static void PopulateEdgeArray(List<Vector3> vertices, List<int> triangles, List<Edge> edges)
        {
            for(int triangleIndex=0;triangleIndex<triangles.Count;triangleIndex+=3)
            {
                edges.Add(CreateEdge(triangleIndex, triangleIndex + 1, vertices, triangles));
                edges.Add(CreateEdge(triangleIndex+1, triangleIndex + 2, vertices, triangles));
                edges.Add(CreateEdge(triangleIndex+2, triangleIndex, vertices, triangles));
            }
        }

        static bool IsOutsideEdge(int edgeIndex, List<Edge> edgesToProcess)
        {
            int previousIndex = edgeIndex - 1;
            int nextIndex = edgeIndex + 1;
            int numberOfEdges = edgesToProcess.Count;
            Edge currentEdge = edgesToProcess[edgeIndex];

            return (previousIndex < 0 || (currentEdge.CompareTo(edgesToProcess[edgeIndex - 1]) != 0)) && (nextIndex >= numberOfEdges || (currentEdge.CompareTo(edgesToProcess[edgeIndex + 1]) != 0));
        }

        static void SortEdges(List<Edge> edgesToProcess)
        {
            edgesToProcess.Sort();
        }

        static void CreateShadowTriangles(List<Vector3> vertices, List<Color> colors, List<int> triangles, List<Vector4> tangents, List<Edge> edges)
        {
            //记录每个顶点的上一条邻边(顺时针方向)和下一条邻边(逆时针方向)的序号
            List<int> previousEdgeIndex = new List<int>();
            List<int> nextEdgeIndex = new List<int>();
            for (int vertexIndex = 0; vertexIndex < vertices.Count; vertexIndex++)
            {
                for (int edgeIndex = 0; edgeIndex < edges.Count; edgeIndex++)
                {
                    if (IsOutsideEdge(edgeIndex, edges))
                    {
                        //如果该边的终点是当前点,那么该点的上一条邻边就是这条边,存储边的序号
                        if (edges[edgeIndex].vertexIndex1 == vertexIndex) previousEdgeIndex.Add(edgeIndex);
                        //如果该边的起点是当前点,那么该点的下一条邻边就是这条边,存储边的序号
                        if (edges[edgeIndex].vertexIndex0 == vertexIndex) nextEdgeIndex.Add(edgeIndex);
                        if (previousEdgeIndex.Count > vertexIndex && nextEdgeIndex.Count > vertexIndex) break;
                    }
                }
            }

            for (int edgeIndex = 0; edgeIndex < edges.Count; edgeIndex++)
            {
                if (IsOutsideEdge(edgeIndex, edges))
                {
                    Edge edge = edges[edgeIndex];
                    tangents[edge.vertexIndex1] = -edge.tangent;
                    //魔改在此,tangents里记录当前边终点上一条邻边的法线反方向, 那么colors就记录终点下一条邻边的法线反方向
                    colors[edge.vertexIndex1] = -edges[nextEdgeIndex[edge.vertexIndex1]].tangent;

                    int newVertexIndex = vertices.Count;
                    vertices.Add(vertices[edge.vertexIndex0]);
                    tangents.Add(-edge.tangent);
                    //魔改在此,tangents里记录当前边起点下一条邻边的法线反方向, 那么colors就记录起点上一条邻边的法线反方向
                    colors.Add(-edges[previousEdgeIndex[edge.vertexIndex0]].tangent);

                    triangles.Add(edge.vertexIndex0);
                    triangles.Add(newVertexIndex);
                    triangles.Add(edge.vertexIndex1);
                }
            }
        }

        static object InterpCustomVertexData(Vec3 position, object[] data, float[] weights)
        {
            return data[0];
        }

        static void InitializeTangents(int tangentsToAdd, List<Vector4> tangents)
        {
            for (int i = 0; i < tangentsToAdd; i++)
                tangents.Add(Vector4.zero);
        }

        public static void GenerateShadowMesh(Mesh mesh, Vector3[] shapePath)
        {
            List<Vector3> vertices = new List<Vector3>();
            List<int> triangles = new List<int>();
            List<Vector4> tangents = new List<Vector4>();
            List<Color> extrusion = new List<Color>();

            // Create interior geometry
            int pointCount = shapePath.Length;
            //这里已修改,我们不需要像官方源码一样存储边中点的数据,所以数组容量就是pointCount
            var inputs = new ContourVertex[pointCount];
            for (int i = 0; i < pointCount; i++)
            {
                //另一条法线的方向后面要存在Color里,这里只需初始化为0,变量名就不改了
                Color extrusionData = new Color(0, 0, 0, 0);
                inputs[i] = new ContourVertex() { Position = new Vec3() { X = shapePath[i].x, Y = shapePath[i].y, Z = 0 }, Data = extrusionData };
            }

            Tess tessI = new Tess();
            tessI.AddContour(inputs, ContourOrientation.Original);
            tessI.Tessellate(WindingRule.EvenOdd, ElementType.Polygons, 3, InterpCustomVertexData);

            var indicesI = tessI.Elements.Select(i => i).ToArray();
            var verticesI = tessI.Vertices.Select(v => new Vector3(v.Position.X, v.Position.Y, 0)).ToArray();
            var extrusionI = tessI.Vertices.Select(v => new Color(((Color)v.Data).r, ((Color)v.Data).g, ((Color)v.Data).b, ((Color)v.Data).a)).ToArray();

            vertices.AddRange(verticesI);
            triangles.AddRange(indicesI);
            extrusion.AddRange(extrusionI);

            InitializeTangents(vertices.Count, tangents);

            List<Edge> edges = new List<Edge>();
            PopulateEdgeArray(vertices, triangles, edges);
            SortEdges(edges);
            CreateShadowTriangles(vertices, extrusion, triangles, tangents, edges);

            Color[] finalExtrusion = extrusion.ToArray();
            Vector3[] finalVertices = vertices.ToArray();
            int[] finalTriangles = triangles.ToArray();
            Vector4[] finalTangents = tangents.ToArray();

            mesh.Clear();
            mesh.vertices = finalVertices;
            mesh.triangles = finalTriangles;
            mesh.tangents = finalTangents;
            mesh.colors = finalExtrusion;
        }
    }
}
