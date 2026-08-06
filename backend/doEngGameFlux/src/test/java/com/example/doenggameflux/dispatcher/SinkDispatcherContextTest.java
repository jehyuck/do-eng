package com.example.doenggameflux.dispatcher;

import static org.junit.jupiter.api.Assertions.assertNotNull;

import com.example.doenggameflux.component.AiDispatcher;
import com.example.doenggameflux.component.DBComponentHttp;
import com.example.doenggameflux.component.TokenDispatcher;
import com.example.doenggameflux.DoEngGameFluxApplication;
import com.example.doenggameflux.contoller.AiGameController;
import com.example.doenggameflux.handler.DispatcherExceptionHandler;
import com.example.doenggameflux.component.MissionDatabaseService;
import com.example.doenggameflux.repository.PictureRepository;
import com.example.doenggameflux.repository.ProgressRepository;
import com.example.doenggameflux.s3.StorageDispatcher;
import io.r2dbc.spi.ConnectionFactory;
import io.r2dbc.spi.ConnectionFactoryMetadata;
import org.springframework.r2dbc.core.DatabaseClient;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.TestPropertySource;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

@SpringBootTest(
        classes = DoEngGameFluxApplication.class,
        webEnvironment = SpringBootTest.WebEnvironment.NONE,
        properties = {
                "spring.autoconfigure.exclude="
                        + "org.springframework.boot.autoconfigure.r2dbc.R2dbcAutoConfiguration,"
                        + "org.springframework.boot.autoconfigure.data.r2dbc.R2dbcDataAutoConfiguration,"
                        + "org.springframework.boot.autoconfigure.jdbc.DataSourceAutoConfiguration,"
                        + "org.springframework.boot.autoconfigure.data.jdbc.JdbcRepositoriesAutoConfiguration"
        })
@ActiveProfiles("experiment")
@Import(SinkDispatcherContextTest.TestConfig.class)
@TestPropertySource(properties = {
        "cloud.aws.credentials.accessKey=test-access-key",
        "cloud.aws.credentials.secretKey=test-secret-key",
        "cloud.aws.s3.bucket=test-bucket",
        "cloud.aws.region.static=ap-northeast-2"
})
class SinkDispatcherContextTest {

    @Autowired
    private TokenDispatcher tokenDispatcher;

    @Autowired
    private AiDispatcher aiDispatcher;

    @Autowired
    private StorageDispatcher storageDispatcher;

    @Autowired
    private DispatcherMetrics dispatcherMetrics;

    @Autowired
    private DispatcherExceptionHandler dispatcherExceptionHandler;

    @Autowired
    private AiGameController aiGameController;

    @Autowired
    private DBComponentHttp dbComponentHttp;

    @MockBean
    private DatabaseClient databaseClient;

    @MockBean
    private PictureRepository pictureRepository;

    @MockBean
    private ProgressRepository progressRepository;

    @MockBean
    private MissionDatabaseService missionDatabaseService;

    @Test
    void sinkDispatcherBeansAreWired() {
        assertNotNull(tokenDispatcher);
        assertNotNull(aiDispatcher);
        assertNotNull(storageDispatcher);
        assertNotNull(dispatcherMetrics);
        assertNotNull(dispatcherExceptionHandler);
        assertNotNull(aiGameController);
        assertNotNull(dbComponentHttp);
    }

    @Configuration
    static class TestConfig {

        @Bean
        ConnectionFactory connectionFactory() {
            ConnectionFactory factory = mock(ConnectionFactory.class);
            ConnectionFactoryMetadata metadata = mock(ConnectionFactoryMetadata.class);
            when(metadata.getName()).thenReturn("mariadb");
            when(factory.getMetadata()).thenReturn(metadata);
            return factory;
        }
    }
}
