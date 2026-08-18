package com.aquasofts.cithub_flutter

import com.huanchengfly.tieba.post.api.models.protos.Page
import com.huanchengfly.tieba.post.api.models.protos.PbContent
import com.huanchengfly.tieba.post.api.models.protos.Post
import com.huanchengfly.tieba.post.api.models.protos.SimpleForum
import com.huanchengfly.tieba.post.api.models.protos.SubPost
import com.huanchengfly.tieba.post.api.models.protos.SubPostList
import com.huanchengfly.tieba.post.api.models.protos.ThreadInfo
import com.huanchengfly.tieba.post.api.models.protos.User
import com.huanchengfly.tieba.post.api.models.protos.frsPage.ForumInfo
import com.huanchengfly.tieba.post.api.models.protos.frsPage.FrsPageResponse
import com.huanchengfly.tieba.post.api.models.protos.frsPage.FrsPageResponseData
import com.huanchengfly.tieba.post.api.models.protos.pbPage.PbPageResponse
import com.huanchengfly.tieba.post.api.models.protos.pbPage.PbPageResponseData
import com.aquasofts.cithub_flutter.native.TiebaModeratorRole
import java.net.URLDecoder
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okio.Buffer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

@RunWith(RobolectricTestRunner::class)
class TiebaProtoClientTest {
    private lateinit var server: MockWebServer

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun forumUsesPinnedProtobufProtocolAndMapsResponse() {
        val response = FrsPageResponse(
            data_ = FrsPageResponseData(
                forum = ForumInfo(
                    id = 64554,
                    name = "长春工程学院",
                    member_num = 1234,
                    thread_num = 5678,
                    avatar = "//tb.himg.baidu.com/example.jpg",
                ),
                page = Page(current_page = 1, total_page = 3, has_more = 1),
                thread_list = listOf(
                    ThreadInfo(
                        id = 9988,
                        threadId = 9988,
                        title = "协议回归帖子",
                        replyNum = 4,
                        viewNum = 42,
                        authorId = 7,
                        forumId = 64554,
                        forumName = "长春工程学院",
                    ),
                ),
                user_list = listOf(User(id = 7, name = "author", nameShow = "作者")),
            ),
        )
        server.enqueue(
            MockResponse()
                .setHeader("Content-Type", "application/x-protobuf")
                .setBody(Buffer().write(response.encode())),
        )
        val context = RuntimeEnvironment.getApplication()
        val client = TiebaProtoClient(
            context,
            RuntimeLogStore(context),
            server.url("/").toString(),
        )

        val page = client.forum("长春工程学院", 1, "reply", false, "", 0)

        assertEquals("64554", page.forum.id)
        assertEquals("协议回归帖子", page.threads.single().title)
        assertEquals("3", page.threads.single().replyCount)
        assertTrue(page.hasMore)
        val request = server.takeRequest()
        assertEquals("/c/f/frs/page?cmd=301001", request.path)
        assertEquals("protobuf", request.getHeader("x_bd_data_type"))
        assertEquals("长春工程学院", URLDecoder.decode(request.getHeader("forum_name"), Charsets.UTF_8))
        assertTrue(request.body.readUtf8().contains("name=\"data\""))
    }

    @Test
    fun miniImageSignatureMatchesTiebaLiteSortedMd5Vector() {
        assertEquals(
            "42961b9881c2d7cb297e9498f9767789",
            miniTiebaSign(linkedMapOf("b" to "2", "a" to "1")),
        )
    }

    @Test
    fun forumMapsOwnerAndAssistantModeratorRoles() {
        val response = FrsPageResponse(
            data_ = FrsPageResponseData(
                forum = ForumInfo(id = 64554, name = "长春工程学院"),
                page = Page(current_page = 1, total_page = 1),
                thread_list = listOf(
                    ThreadInfo(id = 1, threadId = 1, title = "吧主", authorId = 11),
                    ThreadInfo(id = 2, threadId = 2, title = "小吧主", authorId = 12),
                    ThreadInfo(id = 3, threadId = 3, title = "普通用户", authorId = 13),
                ),
                user_list = listOf(
                    User(id = 11, name = "owner", is_manager = 1, is_bawu = 1),
                    User(id = 12, name = "assistant", is_bawu = 1, bawu_type = "assist"),
                    User(id = 13, name = "member"),
                ),
            ),
        )
        server.enqueue(
            MockResponse()
                .setHeader("Content-Type", "application/x-protobuf")
                .setBody(Buffer().write(response.encode())),
        )
        val context = RuntimeEnvironment.getApplication()
        val client = TiebaProtoClient(
            context,
            RuntimeLogStore(context),
            server.url("/").toString(),
        )

        val page = client.forum("长春工程学院", 1, "reply", false, "", 0)

        assertEquals(TiebaModeratorRole.OWNER, page.threads[0].authorModeratorRole)
        assertEquals(TiebaModeratorRole.ASSISTANT, page.threads[1].authorModeratorRole)
        assertEquals(TiebaModeratorRole.NONE, page.threads[2].authorModeratorRole)
    }

    @Test
    fun threadPreviewHydratesReplyAuthorFromPageUserList() {
        val response = PbPageResponse(
            data_ = PbPageResponseData(
                forum = SimpleForum(id = 64554, name = "长春工程学院"),
                page = Page(current_page = 1, total_page = 1),
                thread = ThreadInfo(id = 9988, threadId = 9988, title = "楼中楼作者测试"),
                post_list = listOf(
                    Post(
                        id = 100,
                        floor = 1,
                        author_id = 11,
                        content = listOf(PbContent(type = 0, text = "正文")),
                        sub_post_number = 1,
                        sub_post_list = SubPost(
                            pid = 100,
                            sub_post_list = listOf(
                                SubPostList(
                                    id = 101,
                                    author_id = 12,
                                    content = listOf(PbContent(type = 0, text = "回复")),
                                ),
                            ),
                        ),
                    ),
                ),
                user_list = listOf(
                    User(id = 11, name = "owner", nameShow = "楼主"),
                    User(id = 12, name = "reply", nameShow = "楼中楼用户"),
                ),
            ),
        )
        server.enqueue(
            MockResponse()
                .setHeader("Content-Type", "application/x-protobuf")
                .setBody(Buffer().write(response.encode())),
        )
        val context = RuntimeEnvironment.getApplication()
        val client = TiebaProtoClient(
            context,
            RuntimeLogStore(context),
            server.url("/").toString(),
        )

        val page = client.thread("9988", 64554, "长春工程学院", 1, "asc", false, "", 0)

        assertEquals("楼中楼用户", page.body!!.replies.single().authorNickname)
    }
}
