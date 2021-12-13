# CustomURP2D

## Unity URP 2D管线简单魔改

本文是一个学了10年医的菜鸡医学生转行做游戏一年半以来写的第二篇技术分享文章，水平有限，抛砖引玉，如有误人子弟贻笑大方之处，恳请各位大佬不吝指正

工作室项目是3D人物+贴了手绘2D美图的3D场景，需要2D光照，但Unity的2D管线目前看来不能完全满足需求，没有了默认ForwardRenderer支持的RenderFeatures，没有了3D阴影，遂开始尝试解读这条2D管线的源码实现原理，尝试魔改。我目前使用的Unity版本是2019.4，URP版本是7.5.3，最新版本的URP源码估计跟本篇有出入

首先感谢这篇文章提供的方法。如需魔改URP，要把{工程目录}/Library/PackageCache下的com.unity.render-pipelines.core目录和com.unity.render-pipelines.universal目录剪切到{工程目录}/Packages下

[URP修改权限开放方法](https://zhuanlan.zhihu.com/p/417662954)

### 1.添加RenderFeature

Renderer2D是2D管线的默认renderer，和ForwardRenderer一样是继承自ScriptableRenderer。开放修改权限后先尝试给Renderer2D添加RenderFeatures，我们来看源码，Renderer2D.cs的Setup函数

```c#
//Renderer2D.cs
public override void Setup(ScriptableRenderContext context, ref RenderingData renderingData)
{
    //...... 
    RenderTargetHandle colorTargetHandle;
    RenderTargetHandle depthTargetHandle;

    CommandBuffer cmd = CommandBufferPool.Get("Create Camera Textures");
    CreateRenderTextures(ref cameraData, ppcUsesOffscreenRT, colorTextureFilterMode, cmd, out colorTargetHandle, out depthTargetHandle);
    context.ExecuteCommandBuffer(cmd);
    CommandBufferPool.Release(cmd);

    ConfigureCameraTarget(colorTargetHandle.Identifier(), depthTargetHandle.Identifier());
    
    if (!usingPPV2 && stackHasPostProcess && cameraData.renderType == CameraRenderType.Base)
    {
        m_ColorGradingLutPass.Setup(k_ColorGradingLutHandle);
        EnqueuePass(m_ColorGradingLutPass);
    }

    m_Render2DLightingPass.ConfigureTarget(colorTargetHandle.Identifier(), depthTargetHandle.Identifier());
    EnqueuePass(m_Render2DLightingPass);

    bool requireFinalPostProcessPass =
    !usingPPV2 && lastCameraInStack && !ppcUpscaleRT && stackHasPostProcess && cameraData.antialiasing == AntialiasingMode.FastApproximateAntialiasing;

    if (cameraData.postProcessEnabled)
    {
        RenderTargetHandle postProcessDestHandle =
        lastCameraInStack && !ppcUpscaleRT && !requireFinalPostProcessPass ? RenderTargetHandle.CameraTarget : k_AfterPostProcessColorHandle;

#if POST_PROCESSING_STACK_2_0_0_OR_NEWER
        if (usingPPV2)
        {
            m_PostProcessPassCompat.Setup(cameraTargetDescriptor, colorTargetHandle, postProcessDestHandle);
            EnqueuePass(m_PostProcessPassCompat);
        }
        else
#endif
        {
            m_PostProcessPass.Setup(
            cameraTargetDescriptor,
            colorTargetHandle,
            postProcessDestHandle,
            depthTargetHandle,
            k_ColorGradingLutHandle,
            requireFinalPostProcessPass,
            postProcessDestHandle == RenderTargetHandle.CameraTarget
            );
            EnqueuePass(m_PostProcessPass);
        }
                
        colorTargetHandle = postProcessDestHandle;
    }

    if (requireFinalPostProcessPass)
    {
        m_FinalPostProcessPass.SetupFinalPass(colorTargetHandle);
        EnqueuePass(m_FinalPostProcessPass);
    }
    else if (lastCameraInStack && colorTargetHandle != RenderTargetHandle.CameraTarget)
    {
        m_FinalBlitPass.Setup(cameraTargetDescriptor, colorTargetHandle);
        EnqueuePass(m_FinalBlitPass);
    }
}
```

稍有些长，不过代码意思很明确。创建渲染目标RT，将几个Pass按需初始化和加入执行队列，2D管线里最关键的就是这个Render2DLightingPass。可以看到这段里没有加入RenderFeatures的Pass，而在ForwardRenderer.cs里有将RenderFeature加入队列的代码

```C#
//ForwardRenderer.cs
public override void Setup(ScriptableRenderContext context, ref RenderingData renderingData)
{
    //......
    for (int i = 0; i < rendererFeatures.Count; ++i)
    {
        if(rendererFeatures[i].isActive)
        rendererFeatures[i].AddRenderPasses(this, ref renderingData);
    }
    //......
}
```

我们把这一小段直接原样加进Renderer2D的Setup函数中，然后要修改Renderer2DDataEditor.cs，这样才能让Renderer2DData的Inspector界面中出现底部的AddRenderFeature

看下有RenderFeature列表的ForwardRendererDataEditor是怎么写的

```c#
//ForwardRendererDataEditor.cs
public class ForwardRendererDataEditor : ScriptableRendererDataEditor
{
    //......
    public override void OnInspectorGUI()
    {
        //......
        base.OnInspectorGUI(); // Draw the base UI, contains ScriptableRenderFeatures list
        //......
    }
}
```

可以看到官方注释写到RenderFeature列表是在基类的OnInspectorGUI中绘制的，查一下基类

```C#
//ScriptableRendererDataEditor.cs
public class ScriptableRendererDataEditor : Editor
{
    //......
    public override void OnInspectorGUI()
    {
        if (m_RendererFeatures == null)
            OnEnable();
        else if (m_RendererFeatures.arraySize != m_Editors.Count)
            UpdateEditorList();

        serializedObject.Update();
        DrawRendererFeatureList();
    }
    //......
}
```

很明显有个DrawRendererFeatureList()做了绘制Feature列表的事。回到Renderer2DDataEditor

```c#
//Renderer2DDataEditor.cs
internal class Renderer2DDataEditor : Editor
{
    //......
    public override void OnInspectorGUI()
   {
     //...
   }
   //......
}
```

基类是Editor，不是和ForwardRendererDataEditor一样继承自ScriptableRendererDataEditor。那就试一试直接让Renderer2DDataEditor继承ScriptableRendererDataEditor再调用base.OnInspectorGUI()。(智能提示找不到类或者有编译错误的话注意引用需要的命名空间)

```c#
//修改Renderer2DDataEditor.cs , 继承ScriptableRendererDataEditor
internal class Renderer2DDataEditor : ScriptableRendererDataEditor
{
    //......
    public override void OnInspectorGUI()
   {
       //...
       base.OnInspectorGUI();
   }
   //......
}
```

bingo，添加RenderFeature完成了~我这里目前能正常使用，但不确定这么简单粗暴的魔改会不会出差错。如果是需要用StackCamera，多个Camera用多种Renderer，各自带一个Feature列表的情况，可能会出问题

![添加RenderFeature](https://pic4.zhimg.com/80/v2-d0fd60aad36bd7852f8a9278336a60d3_720w.jpg)



### 2. 添加3D阴影

项目目前需求是既想要人物模型的3D影子又想要2D管线的锥形阴影。先找到ForwardRenderer中渲染主光源影子的部分

```C#
//ForwardRenderer.cs
public sealed class ForwardRenderer : ScriptableRenderer
{
    //...
    MainLightShadowCasterPass m_MainLightShadowCasterPass;
    public ForwardRenderer(ForwardRendererData data) : base(data)
    {
        //...
        m_MainLightShadowCasterPass = new MainLightShadowCasterPass(RenderPassEvent.BeforeRenderingShadows);
    }
    //......
    public override void Setup(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        //......
        bool mainLightShadows = m_MainLightShadowCasterPass.Setup(ref renderingData);
        if (mainLightShadows) EnqueuePass(m_MainLightShadowCasterPass);
    }
}
```

这段代码就是声明并初始化阴影Pass，如果裁剪结果中包含的光源至少影响了一个阴影投射物)，那么把阴影Pass加入执行队列。故技重施直接把这段复制粘贴到Render2D看看，这次不灵了，影子还没出现。经我一番探索，还需要改一个地方，对比一下ForwardRenderer和Renderer2D的SetupCullingParameters函数

```c#
//ForwardRenderer.cs
public override void SetupCullingParameters(ref ScriptableCullingParameters cullingParameters,
ref CameraData cameraData)
{
    bool isShadowCastingDisabled = !UniversalRenderPipeline.asset.supportsMainLightShadows && !UniversalRenderPipeline.asset.supportsAdditionalLightShadows;
    bool isShadowDistanceZero = Mathf.Approximately(cameraData.maxShadowDistance, 0.0f);
    if (isShadowCastingDisabled || isShadowDistanceZero)
    {
        cullingParameters.cullingOptions &= ~CullingOptions.ShadowCasters;
    }

    cullingParameters.maximumVisibleLights = UniversalRenderPipeline.maxVisibleAdditionalLights + 1;
    cullingParameters.shadowDistance = cameraData.maxShadowDistance;
}
```

```C#
//Renderer2D.cs
public override void SetupCullingParameters(ref ScriptableCullingParameters cullingParameters, ref CameraData cameraData)
{
    cullingParameters.cullingOptions = CullingOptions.None;
    cullingParameters.isOrthographic = cameraData.camera.orthographic;
    cullingParameters.shadowDistance = 0.0f;
}  
```

完全不一样阿，需要深入研究这个裁剪参数设置的原理吗? 我直接把ForwardRenderer的SetupCullingParameters代码copy给Renderer2D试下，发现影子出现了......

![既有3D影子又有2D锥形阴影（对不起哈迪斯借用一下大厅背景，SG表打我)](https://pic4.zhimg.com/80/v2-9e4040d7554e17f109aa74b915aab31f_720w.jpg)

仍然是个不确定能一直好用的魔改



## Unity URP 2D管线简单魔改二--添加阴影长度，阴影衰减，张开角度等自定义设置

本文是一个学了10年医的菜鸡医学生转行做游戏一年半以来写的第四篇技术分享文章，水平有限，抛砖引玉，如有误人子弟贻笑大方之处，恳请各位大佬不吝指正。我目前使用的Unity版本是2019.4，URP版本是7.5.3，最新版本的URP源码估计跟本篇有出入

在上一篇解读完URP的2D管线具体渲染光照阴影的全过程后，也就大概知道该怎么修改出一些自己想添加的设置了。本篇主要拣修改部分说，渲染过程的具体解读可看我的上一篇文章

[Unity URP 2D管线源码试解读](https://zhuanlan.zhihu.com/p/429509171)



### 1. 添加光源的阴影长度设置和阴影渐变

用过URP2D光源的朋友都知道，阴影的长度范围是没法控制的，完全是跟着光照范围走。点光源的外半径调到充满差不多光照覆盖全屏时，Frame Debugger里一看阴影贴图的阴影部分都是伸出屏幕外的

![框内为魔改前的默认可调参数，对阴影的控制只有阴影强度](https://pic2.zhimg.com/80/v2-d212fc5ea3faaf98dce7687fb0d612bd_720w.jpg)

在代码里能看到阴影半径是怎么来的

```C#
//RendererLighting.cs
static private void RenderShadows(CommandBuffer cmdBuffer, int layerToRender, Light2D light, float shadowIntensity, RenderTargetIdentifier renderTexture, RenderTargetIdentifier depthTexture)
{
    //...
    if (shadowIntensity > 0)
    {
        //...
        BoundingSphere lightBounds = light.GetBoundingSphere(); 
        float shadowRadius = 1.42f * lightBounds.radius;  //有没有哪位大手子知道官方的1.42这个系数是怎么得来的
        cmdBuffer.SetGlobalFloat("_ShadowRadius", shadowRadius);
        //...
    }
}
```

开始修改，先给光源添加阴影半径和公有属性

```C#
//Light2D.cs
sealed public partial class Light2D : MonoBehaviour
{
   //...
   [Range(0,1)]
   [SerializeField] float m_ShadowIntensity    = 0.0f;
   [Range(0,1)]
   [SerializeField] float m_ShadowVolumeIntensity = 0.0f;

   // 在此添加
   [Range(0,1.42f)]
   [SerializeField] float m_ShadowRadius = 1.42f;  //默认保持神秘的1.42

   /// <summary>
   /// Custom Code : 影子长度
   /// </summary>
   public float shadowRadius { get => m_ShadowRadius; set => m_ShadowRadius = value; }

   //...
}
```

再在Light2D的Inspector界面上添加滑块控制阴影长度

```C#
//Light2DEditor.cs
[CustomEditor(typeof(Light2D))]
internal class Light2DEditor : PathComponentEditor<ScriptablePath>
{
   private static class Styles
   {
      //...
      public static GUIContent generalShadowRadius = EditorGUIUtility.TrTextContent("Shadow Radius", "魔改影子长度");
   }

   //...
   SerializedProperty m_ShadowRadius;

   void OnEnable()
   {
      //...
      m_ShadowRadius = serializedObject.FindProperty("m_ShadowRadius");
   }

   public override void OnInspectorGUI()
   {
      //...
      if (m_LightType.intValue != (int)Light2D.LightType.Global)
      {
         //...
         EditorGUILayout.Slider(m_VolumetricAlpha, 0, 1, Styles.generalVolumeOpacity);
         EditorGUILayout.Slider(m_ShadowIntensity, 0, 1, Styles.generalShadowIntensity);
         if(m_VolumetricAlpha.floatValue > 0)
            EditorGUILayout.Slider(m_ShadowVolumeIntensity, 0, 1, Styles.generalShadowVolumeIntensity);
         //在此添加
         EditorGUILayout.Slider(m_ShadowRadius, 0, 1.42f, Styles.generalShadowRadius);
      }
   }
}
```

最后回管线过程代码里将阴影长度传给shader

```C#
//RendererLighting.cs
static private void RenderShadows(CommandBuffer cmdBuffer, int layerToRender, Light2D light, float shadowIntensity, RenderTargetIdentifier renderTexture, RenderTargetIdentifier depthTexture)
{
    //...
    if (shadowIntensity > 0)
    {
        //...
        BoundingSphere lightBounds = light.GetBoundingSphere(); 
        float shadowRadius = light.shadowRadius * lightBounds.radius; //light.shadowRadius范围是0-1.42, 神秘的1.42
        cmdBuffer.SetGlobalFloat("_ShadowRadius", shadowRadius);
        //...
    }
}
```

就能看到可以控制阴影长度啦

![哈迪斯老师我错了我又来偷素材演示了](https://pic2.zhimg.com/v2-934360bab208854c65b090e24bf9925d_b.gif)

但目前的阴影是没有衰减的，我们尝试添加一下衰减。看看shader里阴影贴图是怎么生成的(简单回顾一下，上一篇文章里已经写过了)

```GLSL
//ShadowGroup2D.shader
Varyings vert (Attributes v)
{
    Varyings o;
    float3 vertexWS = TransformObjectToWorld(v.vertex);  // This should be in world space
    float3 lightDir = _LightPos - vertexWS;
    lightDir.z = 0;

    // Start of code to see if this point should be extruded
    float3 lightDirection = normalize(lightDir);  

    float3 endpoint = vertexWS + (_ShadowRadius * -lightDirection);

    float3 worldTangent = TransformObjectToWorldDir(v.tangent.xyz);
    //计算dot(法线,光照方向),结果>0的都视为面朝光源,要沿反方向投射阴影,sharedShadowTest值为1. 其余情况sharedShadowTest值为0,即该点留在原地不投射.
    float sharedShadowTest = saturate(ceil(dot(lightDirection, worldTangent)));

    // Start of code to calculate offset
    float3 vertexWS0 = TransformObjectToWorld(float3(v.extrusion.xy, 0));
    float3 vertexWS1 = TransformObjectToWorld(float3(v.extrusion.zw, 0));
    float3 shadowDir0 = vertexWS0 - _LightPos;
    shadowDir0.z = 0;
    shadowDir0 = normalize(shadowDir0);

    float3 shadowDir1 = vertexWS1 -_LightPos;
    shadowDir1.z = 0;
    shadowDir1 = normalize(shadowDir1);

    //角上的顶点直接以光源反方向投射,边的中点以边两端顶点的光源反方向的半角向量投射
    float3 shadowDir = normalize(shadowDir0 + shadowDir1);
    //面朝光源的点投射,背离光源的点留在原地
    float3 sharedShadowOffset = sharedShadowTest * _ShadowRadius * shadowDir;

    float3 position;
    position = vertexWS + sharedShadowOffset;
    o.vertex = TransformWorldToHClip(position);

    // RGB - R is shadow value (to support soft shadows), G is Self Shadow Mask, B is No Shadow Mask
    // 这里能看出阴影贴图里的阴影区域就是(1, 0.5, 0)的橙色  
    o.color = 1; // v.color;
    o.color.g = 0.5;
    o.color.b = 0;

    o.uv = TRANSFORM_TEX(v.uv, _MainTex);

    return o;
}

float4 frag (Varyings i) : SV_Target
{
    float4 main = tex2D(_MainTex, i.uv);
    float4 col = i.color;
    col.g = main.a * col.g;              
    return col;
}
```

阴影区域全是统一的橙色。如果我们想要一个从阴影近端到远端的渐变衰减，应该有一个值是近端为1，远端为0，中间为1~0之间的插值。考察代码里的sharedShadowOffset，它是决定阴影Mesh上的顶点需不需要沿光照反方向投射的值，该值在近端为0即该近端顶点不投射，在远端为1。看起来我们把1 - sharedShadowOffset存到顶点的color.r里，传给片元函数会自动完成近端到远端，1~0的线性插值。开始修改(此时只是尝试，并不能确定color.r里存那个渐变值就能得到正确效果)

```GLSL
//ShadowGroup2D.shader
Varyings vert (Attributes v)
{
    //... 
    o.color.r = 1 - sharedShadowTest;
    o.color.g = 0.5;
    o.color.b = 0;
    o.color.a = 1; 
}
```

可以看到渐变有了

[阴影渐变](https://vdn3.vzuu.com/SD/13cbca38-5279-11ec-9f8b-8e920e49e550.mp4?disable_local_cache=1&auth_key=1639385340-0-0-99cb30a89c77452f110fdc72ac67c27a&f=mp4&bu=pico&expiration=1639385340&v=tx)

我们再回顾一下渲染光照贴图时阴影贴图是怎么用的，验证一下这么改的正确性

```GLSL
//LightingUtility.hlsl
#define APPLY_SHADOWS(input, color, intensity)\
if(intensity < 1)\
{\
   half4 shadow = saturate(SAMPLE_TEXTURE2D(_ShadowTex, sampler_ShadowTex, input.shadowUV)); \
   half  shadowIntensity = 1 - (shadow.r * saturate(2 * (shadow.g - 0.5f * shadow.b))); \
   color.rgb = (color.rgb * shadowIntensity) + (color.rgb * intensity*(1 - shadowIntensity));\
}
```

近端起始处shadow.r = 1，代入后shadowIntensity就是0，化简得color.rgb = color.rgb * intensity，阴影强度拉满。末端shadow.r = 0，化简得color.rgb = color.rgb，保持贴图原色无阴影

找一个靠近近端shadow.r = 0.8的位置，代入后shadowIntensity = 0.2，color.rgb = color.rgb * (0.2 + 0.8 * intensity)。这里intensity值是(1 - Inspector面板上的Shadow Intensity)，也就是滑块拉得越大intensity越小，滑块拉到1，intensity就是0。考察拉满时的情况得color.rgb = color.rgb * 0.2，说明靠近近端时是阴影强度大，颜色偏暗，符合从近到远的阴影强度衰减，正确性ok了



### 2. 添加光源中心的偏移(极坐标系表示)，方便随意控制阴影方向(可以做出假的2D平行光照出平行阴影的效果)

URP的默认设置里，阴影方向大致是从光源中心指向阴影投射Mesh的方向，光源中心位置是Light2D挂载在的gameobject的世界Position。这样的话如果想用默认设置做一个等角视角下平行光照出平行阴影的效果，我自己的做法是用Freeform光源，把transform拉得离光照范围很远处，再在EditShape时把Shape画在光照范围的原位置。这种做法感觉太蠢了，不怎么优雅?我想要让光照范围和控制阴影方向的光源中心分离，自由地控制某一片光照区域里给人感觉的"光源方向"

看下管线过程代码里把光源Position传给shader的地方

```C#
//RendererLighting.cs
static private void RenderShadows(CommandBuffer cmdBuffer, int layerToRender, Light2D light, float shadowIntensity, RenderTargetIdentifier renderTexture, RenderTargetIdentifier depthTexture)
{
    //...
    if (shadowIntensity > 0)
    {
        //...
        cmdBuffer.SetGlobalVector("_LightPos", light.transform.position);
    }
}
```

那我们给Light2D添加一个极坐标系角度和半径控制的偏移加到light.transform.position就可以，开始修改

```C#
//Light2D.cs
sealed public partial class Light2D : MonoBehaviour
{
    //...
    //刚才添加的阴影长度
    [Range(0,1.42f)]
    [SerializeField] float m_ShadowRadius = 1.42f;
    
    //在此添加
    [Range(-180f,180f)]
    [SerializeField] float m_LightPositionOffsetAngle;
    [SerializeField] float m_LightPositionOffsetRadius;

    /// <summary>
    /// Custom Code : 影子长度
    /// </summary>
    public float shadowRadius { get => m_ShadowRadius; set => m_ShadowRadius = value; }
   
    /// <summary>
    /// Custom Code : 光源中心偏移角度
    /// </summary>
    public float lightPositionOffsetAngle { get => m_LightPositionOffsetAngle; set => m_LightPositionOffsetAngle = value; }

    /// <summary>
    /// Custom Code : 光源中心偏移半径
    /// </summary>
    public float lightPositionOffsetRadius { get => m_LightPositionOffsetRadius; set => m_LightPositionOffsetRadius = value; }

    //...
}
```

Inspector界面添加属性编辑

```C#
//Light2DEditor.cs
[CustomEditor(typeof(Light2D))]
internal class Light2DEditor : PathComponentEditor<ScriptablePath>
{
   private static class Styles
   {
       //...
       public static GUIContent generalShadowRadius = EditorGUIUtility.TrTextContent("Shadow Radius", "魔改影子长度");
       public static GUIContent lightPositionOffsetAngle = EditorGUIUtility.TrTextContent("ShadowCaster Center Offset Angle", "光源中心偏移角度");
       public static GUIContent lightPositionOffsetRadius = EditorGUIUtility.TrTextContent("ShadowCaster Center Offset Radius", "光源中心偏移半径");
   }

   //...
   SerializedProperty m_ShadowRadius;
   SerializedProperty m_LightPositionOffsetAngle;
   SerializedProperty m_LightPositionOffsetRadius;

   void OnEnable()
   {
       //...
       m_ShadowRadius = serializedObject.FindProperty("m_ShadowRadius");
       m_LightPositionOffsetAngle = serializedObject.FindProperty("m_LightPositionOffsetAngle");
       m_LightPositionOffsetRadius = serializedObject.FindProperty("m_LightPositionOffsetRadius");
   }

   public override void OnInspectorGUI()
   {
      //...
      if (m_LightType.intValue != (int)Light2D.LightType.Global)
      {
         //...
         //Custom ShadowRadius
         EditorGUILayout.Slider(m_ShadowRadius, 0, 1.42f, Styles.generalShadowRadius);

         //Custom LightPositionOffset
         EditorGUILayout.Slider(m_LightPositionOffsetAngle, -180f, 180f, Styles.lightPositionOffsetAngle);
         EditorGUILayout.PropertyField(m_LightPositionOffsetRadius, Styles.lightPositionOffsetRadius);
      }
   }
}
```

修改管线过程代码，把偏移后的光源中心位置传给shader

```C#
//RendererLighting.cs
static private void RenderShadows(CommandBuffer cmdBuffer, int layerToRender, Light2D light, float shadowIntensity, RenderTargetIdentifier renderTexture, RenderTargetIdentifier depthTexture)
{
    //...
    if (shadowIntensity > 0)
    {
        //...
        Vector3 offset = new Vector3(Mathf.Cos(light.lightPositionOffsetAngle * Mathf.Deg2Rad), Mathf.Sin(light.lightPositionOffsetAngle * Mathf.Deg2Rad), 0);
        cmdBuffer.SetGlobalVector("_LightPos", light.transform.position + offset * light.lightPositionOffsetRadius);
    }
}
```

看看效果, ok了

[假平行光](https://vdn3.vzuu.com/SD/1f121ce0-528c-11ec-ab4f-66c2397e5216.mp4?disable_local_cache=1&auth_key=1639385807-0-0-ab8703257c70018477ce45023ae4ac29&f=mp4&bu=pico&expiration=1639385807&v=tx)



### 3. 添加ShadowCaster2D控制自身阴影长度和锥形阴影张开角度的设置

上面控制阴影长度是在光源的属性里，这样的话一个高柱子和一个普通身高角色在假平行光照下的阴影长度就是一样的，这显然不太好，我们得给ShadowCaster2D也添加一个控制自己投出阴影长度的属性，这很简单

在光源中心拉得很远后，可以看到阴影的形状变成条状了，阴影的两条边也变成平行的。美术小姐姐觉得不好看，想让离得很远的平行光源也能照出锥形阴影，可以控制锥形阴影的张开角度，这好像不太简单?

我们看看生成阴影Mesh的部分是怎么写的。具体的全代码可以在我上一篇文章里看，这里只讲需要修改的部分

```c#
//ShadowUtility.cs
//第二个参数shapePath是ShadowCaster2D面板上Edit Shape绘制图形的顶点位置数据
public static void GenerateShadowMesh(Mesh mesh, Vector3[] shapePath)
{
    //...
    int pointCount = shapePath.Length;
    //扩充顶点数,将一条边的中点也加入顶点数组
    var inputs = new ContourVertex[2 * pointCount];
    for (int i = 0; i < pointCount; i++)
    {
        //角上的顶点将自身坐标记录在顶点色.rg和.bw里,计算扩展阴影的方向时使用
        Color extrusionData = new Color(shapePath[i].x, shapePath[i].y, shapePath[i].x, shapePath[i].y);
        int nextPoint = (i + 1) % pointCount;
        //存储角上顶点的坐标,顶点色
        inputs[2*i] = new ContourVertex() { Position = new Vec3() { X = shapePath[i].x, Y = shapePath[i].y, Z=0 }, Data = extrusionData };

        //边的中点顶点将相邻两点的坐标分别记录在顶点色.rg和bw里,计算扩展阴影的方向时使用
        extrusionData = new Color(shapePath[i].x, shapePath[i].y, shapePath[nextPoint].x, shapePath[nextPoint].y);
        Vector2 midPoint = 0.5f * (shapePath[i] + shapePath[nextPoint]);
        //存储边中点的坐标,顶点色
        inputs[2*i+1] = new ContourVertex() { Position = new Vec3() { X = midPoint.x, Y = midPoint.y, Z = 0}, Data = extrusionData };
    }

    //......
}
```

这里我们可以看到，官方代码里添加了多边形的中点到顶点数组里，在顶点色里储存自己的顶点坐标(中点储存边两端顶点的坐标)，传给shader后用来计算顶点的阴影扩展方向。理解是理解了，但是既然阴影扩展方向就是简单的光源方向的反方向，那我直接用顶点坐标和光源坐标算光源方向不就行了? 干嘛要拷贝一份到顶点色里呢? 我们直接不要中点了，想想办法看能不能根据一个顶点所属两条边的法线方向和该点的光照方向之间的关系规律旋转光照方向，形成一种锥形阴影张开角度的效果。这里回顾一下上篇文章提到的官方代码里实现阴影扩展的部分，注意tangents数组里存的是顶点的法线

```C#
//ShadowUtility.cs
static Edge CreateEdge(int triangleIndexA, int triangleIndexB, List<Vector3> vertices, List<int> triangles)
{
    Edge retEdge = new Edge();
    //指定边的起点和终点
    retEdge.AssignVertexIndices(triangles[triangleIndexA], triangles[triangleIndexB]);
            
    Vector3 vertex0 = vertices[retEdge.vertexIndex0];
    vertex0.z = 0;
    Vector3 vertex1 = vertices[retEdge.vertexIndex1];
    vertex1.z = 0;
    //边的方向为起点指向终点. 经我实测,官方的生成算法会保证默认EditShape多边形的所有三角形边方向沿逆时针走
    Vector3 edgeDir = Vector3.Normalize(vertex1 - vertex0);
    //边的法线方向为屏幕朝外和边方向的叉乘, 根据左手定则和逆时针行走的边方向可知法线方向为指向三角形外侧
    retEdge.tangent = Vector3.Cross(-Vector3.forward, edgeDir);
    return retEdge;
}

static void PopulateEdgeArray(List<Vector3> vertices, List<int> triangles, List<Edge> edges)
{
    for(int triangleIndex=0;triangleIndex<triangles.Count;triangleIndex+=3)
    {
        //对三角形数组里的每个三角形生成三条边
        edges.Add(CreateEdge(triangleIndex, triangleIndex + 1, vertices, triangles));
        edges.Add(CreateEdge(triangleIndex+1, triangleIndex + 2, vertices, triangles));
        edges.Add(CreateEdge(triangleIndex+2, triangleIndex, vertices, triangles));
    }
}

static void CreateShadowTriangles(List<Vector3> vertices, List<Color> colors, List<int> triangles, List<Vector4> tangents, List<Edge> edges)
{
    for(int edgeIndex=0; edgeIndex<edges.Count; edgeIndex++)
    {
        if(IsOutsideEdge(edgeIndex, edges))
        {
            Edge edge = edges[edgeIndex];
            //该边的终点法线方向设为该边法线的反方向
            tangents[edge.vertexIndex1] = -edge.tangent;
            
            //添加一个新顶点,坐标为起点的坐标,姑且叫做"新起点"
            int newVertexIndex = vertices.Count;
            vertices.Add(vertices[edge.vertexIndex0]);
            colors.Add(colors[edge.vertexIndex0]);
            //注意新起点的法线和原起点的法线不同
            //原起点的法线是在遍历边时该起点作为另一条边的终点时赋值的,即原起点的法线是当前边顺时针方向那条边法线的反方向
            //而新起点的法线是目前这条边法线的反方向
            tangents.Add(-edge.tangent);
            
            //该边的原起点
            triangles.Add(edge.vertexIndex0);
            //新起点.新起点和原起点的法线分别为该点属于的两条邻边各自的法线反方向,保证该顶点处在背离光源的方向时可以被投射
            triangles.Add(newVertexIndex);
            //该边终点
            triangles.Add(edge.vertexIndex1);
        }
    }
}
```

画个图来形象复盘一下这个将顶点朝光源方向的反向投射创建阴影Mesh的过程吧，用一个最简单的三角形Shape举例。假设我们添加ShadowCaster2D后EditShape出一个三角形(V0,V1,V2)，光源在右上方，先画进入CreateShadowTriangles()前原始三角形(V0,V1,V2)三条边的情况

![](https://pic1.zhimg.com/80/v2-7e480209f96fd97d516682b2b3fab1e8_720w.jpg)

(图中标出了原始三角形各顶点，各边的法线方向，各顶点的法线方向和光源方向。将顶点向光源反方向投射是在shader里实现的，投射条件是夹角(光源,法线)小于90度，可以看到图中V0和V2是满足投射条件的，投射到V0'和V2'，绘制的阴影三角形即V0'V1V2')

之后进入CreateShadowTriangles函数对每条外部的边创建阴影三角形。这里以边V0-V1举例，对于V0创建一个坐标与V0相同的新顶点V3，V3与V0只有法线方向不同，V0的法线方向是N0(即N20的反方向)，V3的法线方向是N3(即N01的反方向)。V0-V1这条边创建的三角形即(V0,V1,V3)，若V0与V3均不满足投射条件或均被投射，那这个三角形就是条不绘制的直线

![](https://pic2.zhimg.com/80/v2-07c6934da8de3322b199307ffec2e8c9_720w.jpg)

(对上一张图的V0-V1(此图的V3-V4)这条边，添加新顶点V3，V0V1V3中只有V0满足投射条件被投射至V0'，画出(V0',V3,V1)这个阴影三角形(此图的V0'V3V4)。对于上一张图的V1-V2（此图的V4-V5)，添加新顶点V4，投射V4至V4'，V2至V2'，画出V1V4'V2')

如果不想让顶点只是单纯沿光源反方向投射，而是做出一个可调节的张开角度效果，该怎么办呢?对于上图的情况来说，想让阴影区域的张开角度扩大，就是改变V4和V3的光源方向，即L4向顺时针转，L3向逆时针转。那对于所有情况该怎么判断哪个点的光源方向需要顺时针还是逆时针转呢?

仔细思考一下，目前的做法里，每个顶点其实在它所属的相邻两条边上用不同的法线方向分别判断了一次相对于光源方向需不需要投射，需要投射那就沿光源反方向投射就完了，投射方向是不需要两条边的法线再参与计算算出来的的。而现在我们想让投射方向根据不同条件决定是顺还是逆时针的旋转，这个条件显然是需要考虑两条边的法线情况。我们继续画图说明

![](https://pic2.zhimg.com/80/v2-407fa4a33f97b2927d2b0f2feafba485_720w.jpg)

(光在两条法线的同一侧时，我们想要的旋转方向就是从光到较近的法线的转向方向。V0V3点的情况如右上的小图表示，V0V3向光的反方向投射时，我们将光的反方向再逆时针旋转某个角度。V1V4点的情况如右下小图所示，将光的反方向顺时针旋转同样的角度)

判断两条法线是否在光的同一侧，就看叉乘结果正负号号是否相等，计算cross(光，近法线)和cross(光，远法线)比较即可。若两条法线在光的同一侧，则投射阴影时光的反方向的顺逆时针旋转方向与从光转到法线的旋转方向一致

再看看两条发现不在同一侧的情况

![](https://pic2.zhimg.com/80/v2-ee64c065429198e8fae52cf0e4c8a77d_720w.jpg)

总结：光在两条法线的不同侧时，设两条法线的半角向量为H。如果dot(光，H)>0，那么投射阴影时光的反方向的顺逆时针旋转方向与从光转到法线的旋转方向相反；如果dot(光，H)<0，那么投射阴影时光的反方向的顺逆时针旋转方向与从光转到法线的旋转方向相同



ok，至此已经明白shader里该怎么旋转光的反方向了，需要的判断条件是光的方向和两条法线的方向。不过官方代码CreateShadowTriangles函数里遍历外部的边时每个顶点是只存了一条邻边的法线的，我们需要给顶点添加存储另一条邻边的法线数据。存在哪里呢?既然感觉官方源码里在顶点Color多存一次坐标是不必要的，那就存在Color里吧，开始修改

```c#
//ShadowUtility.cs
public static void GenerateShadowMesh(Mesh mesh, Vector3[] shapePath)
{
    //...
    int pointCount = shapePath.Length;
    //这里已修改,我们不需要像官方源码一样存储边中点的数据,所以数组容量就是pointCount
    var inputs = new ContourVertex[pointCount];
    for (int i = 0; i < pointCount; i++)
    {
        //另一条法线的方向后面要存在Color里,这里只需初始化为0,变量名就不改了
        Color extrusionData = new Color(0,0,0,0);
        inputs[i] = new ContourVertex() { Position = new Vec3() { X = shapePath[i].x, Y = shapePath[i].y, Z=0 }, Data = extrusionData };
    }

    //... 与源码一致
}

static void CreateShadowTriangles(List<Vector3> vertices, List<Color> colors, List<int> triangles, List<Vector4> tangents, List<Edge> edges)
{
    //记录每个顶点的上一条邻边(顺时针方向)和下一条邻边(逆时针方向)的序号
    List<int> previousEdgeIndex = new List<int>();
    List<int> nextEdgeIndex = new List<int>();
    for(int vertexIndex = 0; vertexIndex < vertices.Count; vertexIndex++)
    {
        for(int edgeIndex = 0; edgeIndex < edges.Count; edgeIndex++)
        {
            if(IsOutsideEdge(edgeIndex, edges))
            {
                //如果该边的终点是当前点,那么该点的上一条邻边就是这条边,存储边的序号
                if (edges[edgeIndex].vertexIndex1 == vertexIndex) previousEdgeIndex.Add(edgeIndex);
                //如果该边的起点是当前点,那么该点的下一条邻边就是这条边,存储边的序号
                if (edges[edgeIndex].vertexIndex0 == vertexIndex) nextEdgeIndex.Add(edgeIndex);
                if (previousEdgeIndex.Count > vertexIndex && nextEdgeIndex.Count > vertexIndex) break;
            }
        }
    }

    for (int edgeIndex=0; edgeIndex<edges.Count; edgeIndex++)
    {
        if(IsOutsideEdge(edgeIndex, edges))
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
```

在shader里实现根据各种条件旋转相应投射方向

```GLSL
//ShadowGroup2D.shader
//添加顺时针和逆时针的旋转矩阵
uniform float4 _ClockwiseRotMatrix;
uniform float4 _AntiClockwiseRotMatrix;
Varyings vert (Attributes v)
{
    Varyings o;
    float3 vertexWS = TransformObjectToWorld(v.vertex);  // This should be in world space
    float3 lightDir = _LightPos - vertexWS;
    lightDir.z = 0;

    // Start of code to see if this point should be extruded
    float3 lightDirection = normalize(lightDir);
    //原投射方向即为光源方向的反方向
    float3 shadowDir = -lightDirection;
    //若该法线不符合投射条件则该顶点留在原地,符合则视为近法线
    float3 worldTangent = TransformObjectToWorldDir(v.tangent.xyz);
    //视为远法线,extrusion是COLOR里存的法线,此处未修改源码的变量名
    float3 anotherTangent = TransformObjectToWorldDir(v.extrusion.xyz);
    //计算dot(近法线,光照方向),结果>0的要投射阴影,sharedShadowTest值为1. 其余情况sharedShadowTest值为0,即该点留在原地不投射.
    float sharedShadowTest = saturate(ceil(dot(lightDirection, worldTangent)));

    //如果近法线符合投射条件
    if (sharedShadowTest > 0)
    {
        //两条法线的半角向量
        float3 halfwayOfTangents = normalize(worldTangent + anotherTangent);
        //光源方向叉乘近法线
        float lightTangentCrossProduct = lightDirection.x * worldTangent.y - lightDirection.y * worldTangent.x;
        //光源方向叉乘远法线
        float lightAnotherTangentCrossProduct = lightDirection.x * anotherTangent.y - lightDirection.y * anotherTangent.x;

        float rotatedDirectionX, rotatedDirectionY;
        if (sign(lightTangentCrossProduct) == sign(lightAnotherTangentCrossProduct))
        {
            //两条法线在光源方向同侧的情况
            //左手系,二维向量叉乘为正是逆时针
            if (lightTangentCrossProduct > 0)
            {
                rotatedDirectionX = dot(shadowDir.xy, _AntiClockwiseRotMatrix.xy);
                rotatedDirectionY = dot(shadowDir.xy, _AntiClockwiseRotMatrix.zw);
            }
            else
            {
                rotatedDirectionX = dot(shadowDir.xy, _ClockwiseRotMatrix.xy);
                rotatedDirectionY = dot(shadowDir.xy, _ClockwiseRotMatrix.zw);
            }
        }
        else
        {
            //两条法线在光源方向异侧的情况
            if (dot(halfwayOfTangents.xy, lightDirection.xy) > 0)
            {
                //两法线的半角向量与光源方向夹角小于90度时,投射方向的旋转方向与从光转到法线的旋转方向相反
                if (lightTangentCrossProduct > 0)
                {
                    rotatedDirectionX = dot(shadowDir.xy, _ClockwiseRotMatrix.xy);
                    rotatedDirectionY = dot(shadowDir.xy, _ClockwiseRotMatrix.zw);
                }
                else
                {
                    rotatedDirectionX = dot(shadowDir.xy, _AntiClockwiseRotMatrix.xy);
                    rotatedDirectionY = dot(shadowDir.xy, _AntiClockwiseRotMatrix.zw);
                }
            }
            else
            {
                //两法线的半角向量与光源方向夹角大于90度时,投射方向的旋转方向与从光转到法线的旋转方向相同
                if (lightTangentCrossProduct > 0)
                {
                    rotatedDirectionX = dot(shadowDir.xy, _AntiClockwiseRotMatrix.xy);
                    rotatedDirectionY = dot(shadowDir.xy, _AntiClockwiseRotMatrix.zw);
                }
                else
                {
                    rotatedDirectionX = dot(shadowDir.xy, _ClockwiseRotMatrix.xy);
                    rotatedDirectionY = dot(shadowDir.xy, _ClockwiseRotMatrix.zw);
                }
            }
        }

        shadowDir = float3(rotatedDirectionX, rotatedDirectionY, 0);
    }

    //背离光源的点向计算得到的旋转后的光源反方向投射,面朝光源的点留在原地
    float3 sharedShadowOffset = sharedShadowTest * _ShadowRadius * shadowDir;

    float3 position;
    position = vertexWS + sharedShadowOffset;
    o.vertex = TransformWorldToHClip(position);

    // RGB - R is shadow value (to support soft shadows), G is Self Shadow Mask, B is No Shadow Mask
    o.color.r = 1 - sharedShadowTest; 
    o.color.g = 0.5;
    o.color.b = 0;

    o.uv = TRANSFORM_TEX(v.uv, _MainTex);

    return o;
}

float4 frag (Varyings i) : SV_Target
{
    float4 main = tex2D(_MainTex, i.uv);
    float4 col = i.color;
    col.g = main.a * col.g;              
    return col;
}
```

给ShadowCaster2D添加角度参数，顺带把阴影长度参数也加了

```C#
//ShadowCaster2D.cs
public class ShadowCaster2D : ShadowCasterGroup2D
{
   //...
   [SerializeField] [Range(0, 30f)] float m_OpenAngle = 0;
   [SerializeField] [Range(0, 1f)] float m_ShadowLength = 1;
   //记录上一帧的角度,用于检测是否需要重绘阴影Mesh
   float m_PreviousOpenAngle = 0;

   /// <summary>
   /// Custom Code: 锥形阴影张角
   /// </summary>
   public float openAngle
   {
       get => m_OpenAngle;
       set => m_OpenAngle = value;
   }

   /// <summary>
   /// Custom Code: 阴影长度
   /// </summary>
   public float shadowLength
   {
       get => m_ShadowLength;
       set => m_ShadowLength = value;
   }

   protected void OnEnable()
   {
       if (m_Mesh == null || m_InstanceId != GetInstanceID())
       {
           m_Mesh = new Mesh();
           ShadowUtility.GenerateShadowMesh(m_Mesh, m_ShapePath);
           m_InstanceId = GetInstanceID();
        }
       m_ShadowCasterGroup = null;
   }

   public void Update()
   {
      //...
      bool rebuildMesh = LightUtility.CheckForChange(m_ShapePathHash, ref m_PreviousPathHash);
      //若改变角度,重绘阴影Mesh
      if (rebuildMesh || m_OpenAngle != m_PreviousOpenAngle)
         ShadowUtility.GenerateShadowMesh(m_Mesh, m_ShapePath);
      //记录此帧角度
      m_PreviousOpenAngle = m_OpenAngle;   
}
```

Inspector界面加可调阴影张开角度，长度属性

```C#
//ShadowCaster2DEditor.cs
[CustomEditor(typeof(ShadowCaster2D))]
internal class ShadowCaster2DEditor : PathComponentEditor<ScriptablePath>
{
    private static class Styles
    {
        //...
        public static GUIContent openAngle = EditorGUIUtility.TrTextContent("Open Angle", "锥形阴影张角");
        public static GUIContent shadowLength = EditorGUIUtility.TrTextContent("Shadow Length", "阴影长度");
    }
    
    SerializedProperty m_OpenAngle;
    SerializedProperty m_ShadowLength;

    public void OnEnable()
    {
        //...
        m_OpenAngle = serializedObject.FindProperty("m_OpenAngle");
        m_ShadowLength = serializedObject.FindProperty("m_ShadowLength");
    }

    public override void OnInspectorGUI()
    {
        //...
        EditorGUILayout.Slider(m_OpenAngle, 0, 30f, Styles.openAngle);
        EditorGUILayout.Slider(m_ShadowLength, 0, 1f, Styles.shadowLength);
    }
}    
```

最后再回到管线过程代码把阴影长度和顺逆时针旋转矩阵传给shader，不需要修改DrawMesh()

```c#
//RendererLighting.cs
static private void RenderShadows(CommandBuffer cmdBuffer, int layerToRender, Light2D light, float shadowIntensity, RenderTargetIdentifier renderTexture, RenderTargetIdentifier depthTexture)
{
    if (shadowIntensity > 0)
    {
        //...
        float shadowRadius = light.shadowRadius * lightBounds.radius;
        List<ShadowCasterGroup2D> shadowCasterGroups = ShadowCasterGroup2DManager.shadowCasterGroups;
        if (shadowCasterGroups != null && shadowCasterGroups.Count > 0)
        {
            //...
            for (int group = 0; group < shadowCasterGroups.Count; group++)
            {
                ShadowCasterGroup2D shadowCasterGroup = shadowCasterGroups[group];
                List<ShadowCaster2D> shadowCasters = shadowCasterGroup.GetShadowCasters();
                //...
                if (shadowCasters != null)
                {
                    for (int i = 0; i < shadowCasters.Count; i++)
                    {
                         ShadowCaster2D shadowCaster = (ShadowCaster2D)shadowCasters[i];
                         //获得ShadowCaster2D里新设置的张开角度的旋转矩阵
                         float sin = Mathf.Sin(shadowCaster.openAngle * Mathf.Deg2Rad);
                         float cos = Mathf.Cos(shadowCaster.openAngle * Mathf.Deg2Rad);
                         Vector4 AntiCWRotMatrix = new Vector4(cos, -sin, sin, cos);
                         Vector4 CWRotMatrix = new Vector4(cos, sin, -sin, cos);
                         if (shadowCaster != null && shadowMaterial != null && shadowCaster.IsShadowedLayer(layerToRender))
                         {
                              if (shadowCaster.castsShadows)
                              {
                                  // Custom Code: 给shader传入单个ShadowCaster2D的阴影长度和旋转矩阵
                                  cmdBuffer.SetGlobalFloat("_ShadowRadius", shadowRadius * shadowCaster.shadowLength);
                                  cmdBuffer.SetGlobalVector("_ClockwiseRotMatrix", CWRotMatrix);
                                  cmdBuffer.SetGlobalVector("_AntiClockwiseRotMatrix", AntiCWRotMatrix);
                                  cmdBuffer.DrawMesh(shadowCaster.mesh, shadowCaster.transform.localToWorldMatrix, shadowMaterial);
                               }                                       
                         }
                    //...
                }     
            }
        }
    }
    //...
}  
```

看看效果

[1](https://vdn3.vzuu.com/SD/14fe625a-59bb-11ec-80b7-5e11b86f6bb6.mp4?disable_local_cache=1&auth_key=1639387168-0-0-b998b2af809ae373a8c007bbbb62e2a2&f=mp4&bu=pico&expiration=1639387168&v=tx)

![2](https://pic1.zhimg.com/v2-7d49ef3c87575c7fb0f9c8f9f0523f4c_b.gif)

(光源随意转方向的效果对了，此次修改文章前的简单做法不对)

[3](https://vdn3.vzuu.com/SD/9a527ffc-59bd-11ec-8b52-e637281d52b7.mp4?disable_local_cache=1&auth_key=1639387190-0-0-01768baaa51b17673a7504618925dcb4&f=mp4&bu=pico&expiration=1639387190&v=tx)

(多边形看起来也没问题)

