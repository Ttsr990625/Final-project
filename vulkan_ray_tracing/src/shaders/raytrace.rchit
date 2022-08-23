#version 460
#extension GL_EXT_ray_tracing : require
#extension GL_EXT_nonuniform_qualifier : enable
#extension GL_EXT_scalar_block_layout : enable
#extension GL_GOOGLE_include_directive : enable
#extension GL_EXT_shader_explicit_arithmetic_types_int64 : require
#extension GL_EXT_buffer_reference2 : require

//#define RR 1        // Using russian roulette
//#define RR_DEPTH 0  // Minimum depth

#include "globals.glsl"
#include "layouts.glsl"
#include "wavefront.glsl"
#include "sampling.glsl"

hitAttributeEXT vec3 attribs;
layout(location = 0) rayPayloadInEXT HitPayload prd;


void main()
{


   
    ObjDesc    objResource = objDesc.i[gl_InstanceCustomIndexEXT];
    MatIndices matIndices  = MatIndices(objResource.materialIndexAddress);
    Materials  materials   = Materials(objResource.materialAddress);
    Indices    indices     = Indices(objResource.indexAddress);
    Vertices   vertices    = Vertices(objResource.vertexAddress);


    ivec3 ind = indices.i[gl_PrimitiveID];


    Vertex v0 = vertices.v[ind.x];
    Vertex v1 = vertices.v[ind.y];
    Vertex v2 = vertices.v[ind.z];

    const vec3 barycentrics = vec3(1.0 - attribs.x - attribs.y, attribs.x, attribs.y);

   
    const vec3 pos            = v0.pos * barycentrics.x + v1.pos * barycentrics.y + v2.pos * barycentrics.z;
    const vec3 world_position = vec3(gl_ObjectToWorldEXT * vec4(pos, 1.0));

    
    const vec3 normal       = v0.nrm * barycentrics.x + v1.nrm * barycentrics.y + v2.nrm * barycentrics.z;
    const vec3 world_normal = normalize(vec3(normal * gl_WorldToObjectEXT));

   
    int               matIdx    = matIndices.i[gl_PrimitiveID];
    WaveFrontMaterial mat       = materials.m[matIdx];


    

    prd.ray_origin = world_position;

    
   

    vec3 hit_value  = mat.emission;  

    vec3  weight    = vec3(1);
    vec3  BSDF      = vec3(1);
    float cos_theta = 1;
    float pdf       = 1;

    vec3 ray_dir;

    if(mat.illum == 3) {           
       
        ray_dir = reflect(gl_WorldRayDirectionEXT, normal);
        BSDF    = mat.specular;
    }
    else if (mat.illum == 2 || mat.illum == 4) {     
       

        float prob_diffuse = length(mat.diffuse) / (length(mat.diffuse) + length(mat.specular));

        if (prob_diffuse > 0.98 || prob_diffuse > rnd(prd.seed)) { 
           
            vec3 tangent, bitangent;
            create_coordinate_system(world_normal, tangent, bitangent);

            if (COSINE_HEMISPHERE_SAMPLING == 1) {   
                ray_dir   = cosine_sample_hemisphere(prd.seed, tangent, bitangent, world_normal);
                cos_theta = dot(ray_dir, world_normal);
                pdf       = cos_theta/M_PI;
            }
            else {                                 
                ray_dir   = sampling_hemisphere(prd.seed, tangent, bitangent, world_normal);
                cos_theta = dot(ray_dir, world_normal);
                pdf       = 1 / M_PI;
            }

           
            vec3 diffuse = mat.diffuse;

            if (mat.textureId >= 0) {
                uint txtId    = mat.textureId + objDesc.i[gl_InstanceCustomIndexEXT].txtOffset;
                vec2 texCoord = v0.texCoord * barycentrics.x + v1.texCoord * barycentrics.y + v2.texCoord * barycentrics.z;

                diffuse *= texture(textureSamplers[nonuniformEXT(txtId)], texCoord).xyz;
            }

            BSDF = prob_diffuse * diffuse / M_PI;
        }
        else {
           
            ray_dir = reflect(gl_WorldRayDirectionEXT, normal);
            ray_dir = ray_dir + (1024 - mat.shininess) / 990 * random_in_unit_sphere(prd.seed);
            BSDF    = mat.specular * (1.0 - prob_diffuse);
        }
    }
    else if (mat.illum == 5) {    
        ray_dir = reflect(gl_WorldRayDirectionEXT, normal);
        BSDF    = mat.specular;
    }
    else if (mat.illum == 6 || mat.illum == 7) {     
       
        bool  front_facing   = dot(-gl_WorldRayDirectionEXT, normal) > 0.0;
        vec3  forward_normal = front_facing ? normal : -normal;
        float eta            = front_facing? (ETA_AIR / mat.ior) : mat.ior;

        vec3  unit_dir  = normalize(gl_WorldRayDirectionEXT);
              cos_theta = min(dot(-unit_dir, forward_normal), 1.0);
        float sin_theta = sqrt(1.0 - cos_theta * cos_theta);

        bool cannot_refract = eta * sin_theta > 1.0;
        bool reflect_condition = mat.illum == 6
            ? cannot_refract
            : cannot_refract || reflectance(cos_theta, eta) > rnd(prd.seed);

        BSDF = vec3(0.98);

        if (reflect_condition) {
            ray_dir = reflect(gl_WorldRayDirectionEXT, forward_normal);
        }
        else {
            BSDF    = mat.transmittance;
            ray_dir = refract(gl_WorldRayDirectionEXT, forward_normal, eta);
        }
    }


   

    vec3 L;
    float light_intensity = pcRay.light_intensity;
    float light_distance = 100000.0;


    float pdf_light       = 1;
    float cos_theta_light = 1;

    if (pcRay.light_type == 0) {        
        vec3 L_dir = pcRay.light_position - world_position;

        light_distance   = length(L_dir);
        light_intensity = pcRay.light_intensity / (light_distance * light_distance);
        L               = normalize(L_dir);
      
        cos_theta_light = dot(L, world_normal);
    }
    else if (pcRay.light_type == 1) {                     
        L = normalize(pcRay.light_position);
        cos_theta_light = dot(L, world_normal);
    }

    if (dot(normal, L) > 0) {
    //    #ifdef RR
    // For Russian-Roulette (minimizing live state)
   // float rrPcont = (depth >= RR_DEPTH) ?
         //               min(max(throughput.x, max(throughput.y, throughput.z)) * state.eta * state.eta + 0.001, 0.95) :
       //                 1.0;
//#endif
        float tMin = 0.001;
        float tMax = light_distance;

        vec3 origin = gl_WorldRayOriginEXT + gl_WorldRayDirectionEXT * gl_HitTEXT;
        vec3 ray_dir = L;

        uint flags = gl_RayFlagsSkipClosestHitShaderEXT;
        prdShadow.is_hit = true;
        prdShadow.seed = prd.seed;

        traceRayEXT(topLevelAS,
            flags,       // rayFlags
            0xFF,        // cullMask
            1,           // sbtRecordOffset
            0,           // sbtRecordStride
            1,           // missIndex
            origin,      // ray origin
            tMin,        // ray min range
            ray_dir,      // ray direction
            tMax,        // ray max range
            1            // payload (location = 1)
        );

        prd.seed = prdShadow.seed;
        float attenuation = 1;

        if (!prdShadow.is_hit) {
         //  hit_value = hit_value + light_intensity*BSDF*cos_theta_light / pdf_light;
            hit_value = hit_value + light_intensity*BSDF*cos_theta_light / pdf_light;
        }
    }


  

    weight = BSDF * cos_theta / pdf;

    prd.ray_dir   = ray_dir;
    prd.hit_value = hit_value;
    prd.weight    = weight;
}

//RayTracing(Point p,Vector3 wr){
    // Contribution from the light source.
 //   L_dir = 0.0;
 //   Uniformly sample the light at x¡¯ (pdf_light = 1 / A);
 //   Shoot a ray from p to x¡¯;
 //   if(the ray is not blocked in the middle)
   //     L_dir = L_i * BSDF * cos ¦È * cos ¦È¡¯ / |x¡¯ - p|^2 / pdf_light ;
	
    // Contribution from other reflectors.
//    L_indir = 0.0;
 //   Uniformly sample the hemisphere toward wi (pdf_hemi = 1 / 2pi);
 //   Trace a ray r(p, wi);
 //   if(ray r hit a non-emitting object at q)
 //       L_indir = hit_value * BSDF * cos ¦È / pdf_hemi ;
    
 //   return L_dir + L_indir;
//}

